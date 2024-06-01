using CSV, DataFrames, Distributions, Plots, Statistics

function simulate_renewables(X, kappa, num_scenarios)
    T = length(X)
    scenarios = Matrix{Float64}(undef, T, num_scenarios)
    for t in 1:T
        sigma_t = kappa[t] * X[t]
        normal_dist = Normal(0, sigma_t)
        for s in 1:num_scenarios
            epsilon_t = rand(normal_dist)
            scenarios[t, s] = max(X[t] + epsilon_t, 0)
        end
    end
    return scenarios
end

function simulate_and_aggregate(renewable_df, kappa_wind, kappa_solar, num_scenarios)
    T = size(renewable_df, 2) - 1
    scenarios_solar = zeros(T, num_scenarios)
    scenarios_wind = zeros(T, num_scenarios)

    for row in eachrow(renewable_df)
        gen_type = row["Gen/Hour"]
        X = [row[i] for i in 2:T+1]  # Convertir fila de DataFrame a vector de Float64
        kappa = occursin("Wind", gen_type) ? kappa_wind : kappa_solar
        scenarios = simulate_renewables(X, kappa, num_scenarios)

        if occursin("Solar", gen_type)
            scenarios_solar .+= scenarios
        elseif occursin("Wind", gen_type)
            scenarios_wind .+= scenarios
        end
    end

    return scenarios_solar, scenarios_wind
end

function monte_carlo_with_stats(scenarios)
    means = mean(scenarios, dims=2)
    ci90 = [quantile(view(scenarios, i, :), [0.05, 0.95]) for i in 1:size(scenarios, 1)]
    ci99 = [quantile(view(scenarios, i, :), [0.005, 0.995]) for i in 1:size(scenarios, 1)]
    return ci90, ci99, means
end

function plot_generation(title, scenarios)
    T = size(scenarios, 1)
    means, ci90, ci99 = monte_carlo_with_stats(scenarios)
    
    # Usar broadcasting para restar los vectores correctamente
    ci90_upper = means .- getindex.(ci90, 1)
    ci90_lower = getindex.(ci90, 2) .- means
    ci99_upper = means .- getindex.(ci99, 1)
    ci99_lower = getindex.(ci99, 2) .- means

    p = plot(1:T, means, ribbon=(ci90_upper, ci90_lower), label="90% CI", fillalpha=0.3, title=title, xlabel="Hour", ylabel="Generation (MW)")
    plot!(p, 1:T, means, ribbon=(ci99_upper, ci99_lower), label="99% CI", fillalpha=0.1)
    return p
end



# Cargar datos y ejecutar la simulación y graficación
renewable_df = CSV.read("Renewables.csv", DataFrame)
kappa_wind = LinRange(0.1470, 0.3092, 24)
kappa_solar = LinRange(0.1020, 0.1402, 24)
num_scenarios = 100

scenarios_solar, scenarios_wind = simulate_and_aggregate(renewable_df, kappa_wind, kappa_solar, num_scenarios)

p_solar = plot_generation("Solar Generation", scenarios_solar)
p_wind = plot_generation("Wind Generation", scenarios_wind)
display(plot(p_solar, p_wind, layout=(2, 1), title="Combined Renewable Generation"))