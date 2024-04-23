using JuMP, CSV, DataFrames, XLSX
using Gurobi # Utiliza el solver GLPK, puedes cambiarlo por otro si prefieres
using Plots

# Carga los datos desde los archivos CSV
demand_df = CSV.read("Demand.csv", DataFrame)
generators_df = CSV.read("Generators.csv", DataFrame)
lines_df = CSV.read("Lines.csv", DataFrame)
bess_df = CSV.read("Bess.csv", DataFrame)

# Potencia base de 100MVA
pot_base = 100

# Conjunto de nodos, tiempos, generadores y líneas
N = unique(demand_df[!, "IdBar"]) # Nodos de 1 a 9
T = 1:(size(demand_df, 2) - 1) # Periodos de tiempo de t = 1 a t = 6
G = 1:size(generators_df, 1) # Generadores
L = 1:size(lines_df, 1) # Líneas de transmisión

B = 1:size(bess_df, 1) # Sistemas de almacenamiento de baterías

# Inicializa el modelo de optimización
model = Model(Gurobi.Optimizer)

# Variables de decisión
@variable(model, p[g in G, t in T] >= 0) # Potencia generada por generador g en tiempo t
@variable(model, theta[n in N, t in T]) # Ángulo del voltaje en nodo n en tiempo t

# Variables de decisión para BESS
@variable(model, e[b in B, t in T] >= 0) # Energia guardada de la batería BESS b en tiempo t
@variable(model, dp[b in B, t in T] >= 0) # Potencia producida de la batería BESS b en tiempo t
@variable(model, ds[b in B, t in T] >= 0) # Potencia storage de la batería BESS b en tiempo t

# Parámetros del modelo
demand = Dict((n, t) => demand_df[n, t+1]/pot_base for n in N for t in T) # Demanda dividida por potencia base
pot_min = Dict(g => generators_df.PotMin[g]/pot_base for g in G) # Potencia mínima dividida por potencia base
pot_max = Dict(g => generators_df.PotMax[g]/pot_base for g in G) # Potencia máxima dividida por potencia base
gen_cost = Dict(g => generators_df.GenCost[g] for g in G) # Costo de generación
ramp = Dict(g => generators_df.Ramp[g]/pot_base for g in G) # Rampa dividida por potencia base
line_max = Dict(l => lines_df.PotMax[l]/pot_base for l in L) # Capacidad máxima de línea dividida por potencia base
reactance = Dict(l => lines_df.Imp[l] for l in L) # Reactancia
b_susceptance = Dict(l => 1/lines_df.Imp[l] for l in L) # Susceptancia de línea (recíproco de la reactancia)
Cap_bateria = Dict(b => bess_df.Cap[b]/pot_base for b in B) # Capacidad de baterias
Horas_bateria = Dict(b => bess_df.Horas[b] for b in B) # Horas de baterias
Rend_bateria = Dict(b => bess_df.Rend[b] for b in B) # Rendimiento de baterias
Einicial_bateria = Dict(b => bess_df.E_inicial[b] for b in B) # Energia inicial de baterias
Efinal_bateria = Dict(b => bess_df.E_final[b] for b in B) # Energia final de baterias
# Restricciones del modelo

# Satisfaccion de demanda
@constraint(model, demanda[n in N, t in T],
        sum(p[g, t] for g in G if generators_df.BarConexion[g] == n) +
        sum(dp[b, t] - ds[b, t] for b in B if bess_df.BarConexion[b] == n) -
        sum(b_susceptance[l] * (theta[lines_df.BarIni[l], t] - theta[lines_df.BarFin[l], t]) for l in L if lines_df.BarIni[l] == n) -
        sum(b_susceptance[l] * (theta[lines_df.BarFin[l], t] - theta[lines_df.BarIni[l], t]) for l in L if lines_df.BarFin[l] == n)
        == demand[n, t])

# Fijar el ángulo del nodo slack (nodo 1) a 0 para todos los periodos
for t in T
    @constraint(model, theta[1, t] == 0)
end

# Límites de generación de cada generador
for g in G, t in T
    @constraint(model, pot_min[g] <= p[g, t] <= pot_max[g])
end

# Restricciones de rampa
for g in G, t in 2:length(T)
   @constraint(model, -ramp[g] <= p[g, t] - p[g, t-1] <= ramp[g])
end

# Capacidad de las líneas de transmisión
for l in L, t in T
    @constraint(model, b_susceptance[l]*(theta[lines_df.BarIni[l], t] - theta[lines_df.BarFin[l], t]) <= line_max[l])
end

# Restricciones de las baterías BESS
for b in B, t in T
    # Restricciones para la capacidad de almacenamiento de la batería
    storage_capacity = Horas_bateria[b] * Cap_bateria[b]
    @constraint(model, e[b, t] <= storage_capacity)
    
    # Restricciones para la carga de la batería
    @constraint(model, ds[b, t] <= Cap_bateria[b])

    # Restricciones para la descarga de la batería
    @constraint(model, dp[b, t] <= Cap_bateria[b])

    # Dinámica de la batería
    if t>1
        @constraint(model, e[b, t] == e[b, t-1] + ds[b, t]*Rend_bateria[b] - dp[b, t]/Rend_bateria[b])
    elseif t==1
        @constraint(model, e[b, 1] == storage_capacity * Efinal_bateria[b] + ds[b, 1]*Rend_bateria[b] - dp[b, 1]/Rend_bateria[b])
    end
    if t == last(T)
        @constraint(model, e[b, t] == storage_capacity * Efinal_bateria[b])
    end
end

# Función objetivo: minimizar el costo total
@objective(model, Min, sum(gen_cost[g] * p[g, t] for g in G for t in T))

# Resolver el modelo
optimize!(model)

# Extraer la solución
solucion_potencia = value.(p)*pot_base
solucion_angulos = value.(theta)
solucion_potencia_producida_bateria = value.(dp)*pot_base
solucion_potencia_guardada_bateria = value.(ds)*pot_base
solucion_estadodecarga = value.(e)*pot_base
costo_total = objective_value(model)*pot_base


# Imprimir la solución
println("Potencia generada por generador y tiempo:")
println(solucion_potencia)

println("Ángulo del voltaje en nodo y tiempo:")
println(solucion_angulos)

println("Potencia guardada de la batería BESS:")
println(solucion_potencia_producida_bateria)

println("Potencia descargada de la batería BESS:")
println(solucion_potencia_guardada_bateria)

println("Energia de la batería BESS:")
println(solucion_estadodecarga)


#println("Precios sombra de la demanda por nodo y tiempo:")
#for n in N, t in T
#    preciodual = dual(demanda[n, t])
#    println("Precio sombra del nodo $n en el tiempo $t: $preciodual")
#end
println("------------------------------------------------------------")
println("Costos totales de generación")
println(costo_total)


# Crear matriz para almacenar los valores duales
precios_sombra = Array{Float64}(undef, length(N), length(T))

# Rellenar matriz con los precios sombra
for n in N
    for t in T
        precios_sombra[n, t] = dual(demanda[n, t])
    end
end

# Imprimir la matriz de precios sombra redondeada a dos decimales
println("Matriz de precios sombra (Nodos x Tiempos):")
for n in N
    for t in T
        print(round(precios_sombra[n, t], digits=2), " ")
    end
    println()  # Nueva línea para cada nodo
end
