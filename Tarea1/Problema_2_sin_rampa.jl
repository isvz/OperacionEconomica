using JuMP, CSV, DataFrames, XLSX
using Gurobi  # Utilizar Gurobi como solver

# Carga de datos
demand_df = CSV.read("Demand.csv", DataFrame)
generators_df = CSV.read("Generators.csv", DataFrame)
lines_df = CSV.read("Lines2.csv", DataFrame)

# Potencia base
pot_base = 100

# Conjuntos de nodos, periodos de tiempo, generadores y líneas
N = 1:9 # Nodos del 1 al 9
T = 1:6 # Periodos de tiempo de t = 1 a t = 6
G = 1:size(generators_df, 1) # Generadores
L = 1:size(lines_df, 1) # Líneas de transmisión

# Inicialización del modelo de optimización
model = Model(Gurobi.Optimizer)

# Variables de decisión
@variable(model, p[g in G, t in T] >= 0) # Potencia generada por cada generador g en el tiempo t
@variable(model, theta[n in N, t in T]) # Ángulo de voltaje en el nodo n en el tiempo t
@variable(model, p_insatisfecha[n in N, t in T] >= 0) # Potencia insatisfecha en el nodo n en el tiempo t

# Parámetros del modelo
demand = Dict((n, t) => demand_df[n, t+1]/pot_base for n in N for t in T)
pot_min = Dict(g => generators_df.PotMin[g]/pot_base for g in G)
pot_max = Dict(g => generators_df.PotMax[g]/pot_base for g in G)
gen_cost = Dict(g => generators_df.GenCost[g] for g in G)
ramp = Dict(g => generators_df.Ramp[g]/pot_base for g in G)
line_max = Dict(l => lines_df.PotMax[l]/pot_base for l in L)
b_susceptance = Dict(l => 1/lines_df.Imp[l] for l in L)

# Restricciones del modelo
@constraint(model, demanda[n in N, t in T], 
            sum(p[g, t] for g in G if generators_df.BarConexion[g] == n) - 
            sum(b_susceptance[l]*(theta[lines_df.BarIni[l], t] - theta[lines_df.BarFin[l], t]) for l in L if lines_df.BarIni[l] == n) -
            sum(b_susceptance[l]*(theta[lines_df.BarFin[l], t] - theta[lines_df.BarIni[l], t]) for l in L if lines_df.BarFin[l] == n) ==
            demand[n, t] - p_insatisfecha[n, t])

# Límites de generación
for g in G, t in T
    @constraint(model, pot_min[g] <= p[g, t] <= pot_max[g])
end

# Capacidad de las líneas de transmisión
for l in L, t in T
    @constraint(model, b_susceptance[l]*(theta[lines_df.BarIni[l], t] - theta[lines_df.BarFin[l], t]) <= line_max[l])
end

# Fijar el ángulo del nodo slack (nodo 1) a 0 para todos los periodos
for t in T
    @constraint(model, theta[1, t] == 0)
end

# Función objetivo: minimizar el costo total incluyendo multas por demanda insatisfecha
multa = 30  # $/MW
@objective(model, Min, sum(gen_cost[g] * p[g, t] for g in G for t in T) + multa * sum(p_insatisfecha[n, t] for n in N for t in T))

# Resolución del modelo
optimize!(model)

# Extracción e impresión de las soluciones prímales
solucion_potencia = value.(p)*pot_base
solucion_angulos = value.(theta)
solucion_insatisfecha = value.(p_insatisfecha)*pot_base
solucion_potencia_no_sat = value.(p_insatisfecha)*pot_base

# Imprimir el valor de la función objetivo
valor_objetivo = objective_value(model)
println("Valor de la función objetivo: ", valor_objetivo*pot_base)

# Impresión de las soluciones prímales
println("Potencia generada por generador y tiempo:")
println(solucion_potencia)
println("Potencia insatisfecha por nodo y tiempo:")
println(solucion_insatisfecha)

# Impresión de las soluciones duales (precios sombra)
#println("Precios sombra de la demanda por nodo y tiempo:")
#for n in N, t in T
#    println("Precio sombra en nodo ", n, " en tiempo ", t, ": ", dual(demanda[n, t]))
#end

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

# Escribir los precios sombra en un archivo Excel
XLSX.openxlsx("precios_sombra_p2.xlsx", mode="w") do xf
    sheet = XLSX.addsheet!(xf, "Precios Sombra")
    for n in N
        for t in T
            XLSX.setdata!(sheet, XLSX.CellRef(n+1, t+1), round(precios_sombra[n, t], digits=2))
        end
    end
    # Agregar etiquetas de tiempo como cabecera
    for t in T
        XLSX.setdata!(sheet, XLSX.CellRef(1, t+1), "Tiempo $t")
    end
    # Agregar etiquetas de nodo como cabecera de fila
    for n in N
        XLSX.setdata!(sheet, XLSX.CellRef(n+1, 1), "Nodo $n")
    end
end