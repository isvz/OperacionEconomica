using JuMP, CSV, DataFrames, XLSX, Plots
include("unit_commitment_eval.jl")

function main()
    # Carga los datos desde los archivos CSV
    buses_df = CSV.read("Buses.csv", DataFrame)
    demand_df = CSV.read("Demanda.csv", DataFrame)
    generators_df = CSV.read("Generators.csv", DataFrame)
    lines_df = CSV.read("Lines.csv", DataFrame)
    estado_gen90_df = CSV.read("estado_generadores90.csv", DataFrame)
    estado_gen99_df = CSV.read("estado_generadores99.csv", DataFrame)

    n_escenarios = 100

    # Verificación de la solución
    sum_costo90 = 0
    sum_costo99 = 0
    frecuencia_90 = 0
    frecuencia_99 = 0
    for i in 0:n_escenarios-1
        println("Escenario $(i + 1)")
        renewable_df = CSV.read("simulation/simulated_data_$(i).csv", DataFrame)
        model_90, p, u, theta, gen_cost, fixed_cost, startup_cost, pot_base = unit_commitment_eval(buses_df, demand_df, generators_df, lines_df, renewable_df, estado_gen90_df)

        if termination_status(model_90) == MOI.OPTIMAL
            # Imprimir el valor de la función objetivo y la solución
            valor_objetivo = objective_value(model_90)
            sum_costo90 += valor_objetivo * pot_base
        else
            println("El modelo 90 no tiene una solución óptima en el escenario $(i). Estado de terminación: ", termination_status(model_90))
            frecuencia_90 += 1
        end

        model_99, p, u, theta, gen_cost, fixed_cost, startup_cost, pot_base = unit_commitment_eval(buses_df, demand_df, generators_df, lines_df, renewable_df, estado_gen99_df)
        if termination_status(model_99) == MOI.OPTIMAL
            # Imprimir el valor de la función objetivo y la solución
            valor_objetivo = objective_value(model_99)
            sum_costo99 += valor_objetivo  * pot_base
        else
            println("El modelo 99 no tiene una solución óptima en el escenario $(i). Estado de terminación: ", termination_status(model_99))
            frecuencia_99 += 1
        end
    end

    println("Promedio con caso IC90: ", sum_costo90/(100-frecuencia_90))
    println("Promedio con caso IC99: ", sum_costo99/(100-frecuencia_99))
    println("Frecuencia con caso IC90: ", frecuencia_90)
    println("Frecuancia con caso IC99: ", frecuencia_99)
end

main()
