using JuMP, CSV, DataFrames, Gurobi

function unit_commitment_eval(buses_df::DataFrame, demand_df::DataFrame, generators_df::DataFrame, lines_df::DataFrame, renewable_df::DataFrame, GenEstate::DataFrame)
    # Convertir las columnas relevantes a cadenas
    generators_df.Bus = string.(generators_df.Bus)
    lines_df.FromBus = string.(lines_df.FromBus)
    lines_df.ToBus = string.(lines_df.ToBus)

    # Potencia base de 100MVA
    pot_base = 100
    M = 1e6  # Una constante grande

    # Conjunto de nodos, tiempos, generadores y líneas
    N = 1:size(buses_df, 1) # Nodos
    T = 1:size(demand_df, 2) - 1 # Periodos de tiempo (24 horas)
    G = 1:size(generators_df, 1) # Generadores
    L = 1:size(lines_df, 1) # Líneas de transmisión

    # Inicializa el modelo de optimización
    model = Model(Gurobi.Optimizer)
    set_optimizer_attribute(model, "MIPGap", 0.001)  # Ajusta el gap a 0.001%

    # Variables de decisión
    @variable(model, p[g in G, t in T] >= 0) # Potencia generada por generador g en tiempo t
    @variable(model, theta[n in N, t in T]) # Ángulo del voltaje en nodo n en tiempo t
    @variable(model, u[g in G, t in T], Bin) # Variable binaria para encendido de generador g en tiempo t
    @variable(model, v[g in G, t in T], Bin) # Variable binaria para apagado de generador g en tiempo t
    # @variable(model, w[g in G, t in T], Bin) # Variable binaria para estado ON/OFF de generador g en tiempo t -----> Ahora es un parametro

    # Parámetros del modelo
    demand = Dict((n, t) => demand_df[n, t+1]/pot_base for n in 1:size(demand_df, 1) for t in T)
    pot_min = Dict(g => generators_df.Pmin[g]/pot_base for g in G)
    pot_max = Dict(g => generators_df.Pmax[g]/pot_base for g in G)
    gen_cost = Dict(g => generators_df.VariableCost[g] for g in G)
    fixed_cost = Dict(g => generators_df.FixedCost[g] for g in G)
    startup_cost = Dict(g => generators_df.StartUpCost[g] for g in G)
    ramp = Dict(g => generators_df.Ramp[g]/pot_base for g in G)
    line_max = Dict(l => lines_df.MaxFlow[l]/pot_base for l in L)
    b_susceptance = Dict(l => 1/lines_df.Reactance[l] for l in L)

    W = Dict((g, t) => GenEstate[g, t+1] for g in G for t in T) 

    # Parametros de Reserva
    # RESup = Dict(t => (Interval."Upper"[t] - Interval."Prom"[t])/pot_base for t in T) #Dado que el estado es un parametro no es necesatio
    # RESdown = Dict(t => (Interval."Prom"[t] - Interval."Lower"[t])/pot_base for t in T)

    
    # Identificar generadores renovables
    renewable_generators = [generators_df.Generator[g] for g in G if occursin("Wind", generators_df.Generator[g]) || occursin("Solar", generators_df.Generator[g])]
    renewable_profile = Dict((g, t) => renewable_df[renewable_df."Gen/Hour" .== g, t+1][1]/pot_base for g in renewable_generators for t in T)
    renewable_indices = Dict(g => findfirst(x -> x == g, generators_df.Generator) for g in renewable_generators)
    is_renewable = Dict(g => generators_df.Generator[g] in renewable_generators for g in G)

    # Ajustar el perfil de generación renovable para que esté dentro de los límites
    for g in renewable_generators
        idx = renewable_indices[g]
        for t in T
            if renewable_profile[g, t] < pot_min[idx]
                renewable_profile[g, t] = pot_min[idx]
            elseif renewable_profile[g, t] > pot_max[idx]
                renewable_profile[g, t] = pot_max[idx]
            end
        end
    end

    # Función para convertir cadenas de Bus a enteros de manera segura
    function safe_parse_bus(bus)
        if bus == "missing"
            return missing
        else
            return parse(Int, replace(bus, "Bus" => ""))
        end
    end

    # Restricciones del modelo
    # 1. Satisfacción de la demanda en cada nodo y tiempo
    @constraint(model, [n in N, t in T],
        sum(p[g, t] for g in G if safe_parse_bus(generators_df.Bus[g]) == n) - 
        sum(b_susceptance[l]*(theta[safe_parse_bus(lines_df.FromBus[l]), t] - theta[safe_parse_bus(lines_df.ToBus[l]), t]) for l in L if safe_parse_bus(lines_df.FromBus[l]) == n) -
        sum(b_susceptance[l]*(theta[safe_parse_bus(lines_df.ToBus[l]), t] - theta[safe_parse_bus(lines_df.FromBus[l]), t]) for l in L if safe_parse_bus(lines_df.ToBus[l]) == n) == demand[n, t])

    # 2. Límites de generación de cada generador (incluyendo renovables)
    for g in G, t in T
        if is_renewable[g]
            renewable_gen = generators_df.Generator[g]
            @constraint(model, p[g, t] == renewable_profile[renewable_gen, t])
        else
            @constraint(model, p[g, t] >= pot_min[g] * W[g, t])
            @constraint(model, p[g, t] <= pot_max[g] * W[g, t])
        end
    end

    # 3. Capacidad de las líneas de transmisión
    for l in L, t in T
        @constraint(model, -line_max[l] <= b_susceptance[l]*(theta[safe_parse_bus(lines_df.FromBus[l]), t] - theta[safe_parse_bus(lines_df.ToBus[l]), t]) <= line_max[l])
    end

    # 4. Restricciones de rampa (excluir para generadores solares y eólicos)
    for g in G, t in 2:length(T)
        if !is_renewable[g]
            @constraint(model, p[g, t] - p[g, t-1] <= ramp[g])
            @constraint(model, p[g, t-1] - p[g, t] <= ramp[g])
        end
    end

    # 5. Fijar el ángulo del nodo slack (nodo 1) a 0 para todos los periodos
    for t in T
        @constraint(model, theta[1, t] == 0)
    end

    # 6. Relación entre encendido, apagado y estado para generadores no renovables
    for g in G
        if !is_renewable[g]
            @constraint(model, W[g, 1] - 0 == u[g, 1] - v[g, 1])
            for t in 2:length(T)
                @constraint(model, W[g, t] - W[g, t-1] == u[g, t] - v[g, t])
            end
        end
    end

    # 7. Tiempo mínimo de encendido para generadores no renovables
    for g in G
        if !is_renewable[g]
            for t in 1:(length(T) - generators_df.MinUP[g])
                @constraint(model, sum(W[g, k] for k in t:(t + generators_df.MinUP[g] - 1)) >= generators_df.MinUP[g] * u[g, t])
            end
            for t in (length(T) - generators_df.MinUP[g] + 1):length(T)
                @constraint(model, sum(W[g, k] - u[g, t] for k in t:length(T)) >= 0)
            end
        end
    end

    # 8. Tiempo mínimo de apagado para generadores no renovables
    for g in G
        if !is_renewable[g]
            for t in 1:(length(T) - generators_df.MinDW[g])
                @constraint(model, sum(1 - W[g, k] for k in t:(t + generators_df.MinDW[g] - 1)) >= generators_df.MinDW[g] * v[g, t])
            end
            for t in (length(T) - generators_df.MinDW[g] + 1):length(T)
                @constraint(model, sum(1 - W[g, k] - v[g, t] for k in t:length(T)) >= 0)
            end
        end
    end

    #for t in T
    # # 9. Requisitos de reserva hacia arriba
    #     @constraint(model, sum((pot_max[g] * W[g, t]) for g in G if !is_renewable[g]) <= sum(demand[n, t] for n in N) + RESup[t])

    # # 10. Requisitos de reserva hacia abajo
    #     @constraint(model, sum((pot_max[g] * W[g, t]) for g in G if !is_renewable[g]) >= sum(demand[n, t] for n in N) - RESdown[t])
    # end 

    ## Ambas restricciones ya no son necesarias, dado que son solo parametros

    # Asegurarse de que las variables binarias reflejen el estado de los generadores renovables
    for g in keys(renewable_indices)
        idx = renewable_indices[g]
        for t in T
            @constraint(model, p[idx, t] <= M * W[idx, t])
            @constraint(model, p[idx, t] >= 0 * W[idx, t])  # Asegura que w sea 1 si p > 0
            #@constraint(model, W[idx, t] <= 1)  # Asegura que w no sea mayor que 1
        end
    end

    # Función objetivo: minimizar el costo total
    @objective(model, Min, sum(gen_cost[g] * p[g, t]  + startup_cost[g] * u[g, t] for g in G for t in T))

    # Resolver el modelo
    optimize!(model)

    return model, p, u, theta, gen_cost, fixed_cost, startup_cost, pot_base

end
