using JuMP, CSV, DataFrames, XLSX, Plots
include("unit_commitment.jl")

function main()
    # Carga los datos desde los archivos CSV
    buses_df = CSV.read("Buses.csv", DataFrame)
    demand_df = CSV.read("Demanda.csv", DataFrame)
    generators_df = CSV.read("Generators.csv", DataFrame)
    lines_df = CSV.read("Lines.csv", DataFrame)
    renewable_df = CSV.read("Renewables.csv", DataFrame)
    intervalo_90 = CSV.read("simulation/intervalo_90_renewable.csv", DataFrame)
    intervalo_99 = CSV.read("simulation/intervalo_90_renewable.csv", DataFrame)

    # Llamar a la función unit_commitment
    model, p, w, u, theta, gen_cost, fixed_cost, startup_cost, pot_base = unit_commitment(buses_df, demand_df, generators_df, lines_df, renewable_df, intervalo_90)

    # Verificación de la solución
    if termination_status(model) == MOI.OPTIMAL
        # Imprimir el valor de la función objetivo y la solución
        valor_objetivo = objective_value(model)
        println("Valor de la función objetivo: ", valor_objetivo * pot_base)

        # Costos desglosados
        costo_startup = sum(value(u[g, t]) * startup_cost[g] for g in 1:length(generators_df.Generator) for t in 1:24) * pot_base
        costo_no_load = sum(value(w[g, t]) * fixed_cost[g] for g in 1:length(generators_df.Generator) for t in 1:24) * pot_base
        costo_variable = sum(value(p[g, t]) * gen_cost[g] for g in 1:length(generators_df.Generator) for t in 1:24) * pot_base
        println("Costo de start-up: ", costo_startup)
        println("Costo de no-load: ", costo_no_load)
        println("Costo variable: ", costo_variable)

        # Guardar los costos en un archivo Excel
        costos_df = DataFrame(Variable=["Costo Total", "Costo de start-up", "Costo de no-load", "Costo variable"],
                              Valor=[valor_objetivo * pot_base, costo_startup, costo_no_load, costo_variable])
        XLSX.openxlsx("costos_unit_commitment.xlsx", mode="w") do xf
            XLSX.writetable!(xf["Sheet1"], Tables.columntable(costos_df))
        end

        # Extraer e imprimir la solución
        solucion_potencia = Array(value.(p)) * pot_base
        solucion_angulos = Array(value.(theta))

        # Crear el estado ON/OFF de cada generador en cada hora
        estado_generadores = DataFrame(Generador=generators_df.Generator)
        for t in 1:24
            estado_generadores[!, Symbol("Hora_$t")] = [value(w[g, t]) for g in 1:length(generators_df.Generator)]
        end
        println("Estado ON/OFF de cada generador en cada hora:")
        println(estado_generadores)

        # Guardar el estado ON/OFF en un archivo Excel
        XLSX.openxlsx("estado_generadores.xlsx", mode="w") do xf
            XLSX.writetable!(xf["Sheet1"], Tables.columntable(estado_generadores))
        end

        # Crear el DataFrame de generación horaria de cada generador
        generacion_df = DataFrame(Generador=generators_df.Generator)
        for t in 1:24
            generacion_df[!, Symbol("Hora_$t")] = [value(p[g, t]) * pot_base for g in 1:length(generators_df.Generator)]
        end
        println("Generación de cada generador en cada hora:")
        println(generacion_df)

        # Guardar la generación horaria en un archivo Excel
        XLSX.openxlsx("generacion_por_hora.xlsx", mode="w") do xf
            XLSX.writetable!(xf["Sheet1"], Tables.columntable(generacion_df))
        end

        # Gráfico de demanda total y generación de cada generador
        demanda_total = [sum(demand_df[n, t+1] for n in 1:size(demand_df, 1)) for t in 1:24]
        generaciones = [sum(value(p[g, t]) for g in 1:length(generators_df.Generator)) for t in 1:24]

        plot(1:24, demanda_total, label="Demanda Total", xlabel="Hora", ylabel="MW", title="Demanda Total y Generación por Hora", legend=:bottomright)
        for g in 1:length(generators_df.Generator)
            plot!(1:24, [value(p[g, t]) * pot_base for t in 1:24], label=string("Generador ", generators_df.Generator[g]))
        end
        savefig("generacion_demanda.png")
    else
        println("El modelo no tiene una solución óptima. Estado de terminación: ", termination_status(model))
    end
end

main()