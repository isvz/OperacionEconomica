using JuMP, CSV, DataFrames, XLSX
using Gurobi  # Cambié GLPK por Gurobi, ya que lo mencionas en tu enunciado inicial

# Carga los datos desde los archivos CSV
demand_df = CSV.read("Demand.csv", DataFrame)
generators_df = CSV.read("Generators.csv", DataFrame)
lines_df = CSV.read("Lines.csv", DataFrame)

# Potencia base de 100MVA
pot_base = 100

# Conjunto de nodos, tiempos, generadores y líneas
N = 1:9 # Nodos de 1 a 9
T = 1:6 # Periodos de tiempo de t = 1 a t = 6
G = 1:size(generators_df, 1) # Generadores
L = 1:size(lines_df, 1) # Líneas de transmisión

# Inicializa el modelo de optimización
model = Model(Gurobi.Optimizer)

# Variables de decisión
@variable(model, p[g in G, t in T] >= 0) # Potencia generada por generador g en tiempo t
@variable(model, theta[n in N, t in T]) # Ángulo del voltaje en nodo n en tiempo t

# Parámetros del modelo
demand = Dict((n, t) => demand_df[n, t+1]/pot_base for n in N for t in T)
pot_min = Dict(g => generators_df.PotMin[g]/pot_base for g in G)
pot_max = Dict(g => generators_df.PotMax[g]/pot_base for g in G)
gen_cost = Dict(g => generators_df.GenCost[g] for g in G)
ramp = Dict(g => generators_df.Ramp[g]/pot_base for g in G)
line_max = Dict(l => lines_df.PotMax[l]/pot_base for l in L)
b_susceptance = Dict(l => 1/lines_df.Imp[l] for l in L)

# Restricciones del modelo
# Satisfacción de la demanda en cada nodo y tiempo con nombre para restricciones
@constraint(model, demanda[n in N, t in T],
    sum(p[g, t] for g in G if generators_df.BarConexion[g] == n) - 
    sum(b_susceptance[l]*(theta[lines_df.BarIni[l], t] - theta[lines_df.BarFin[l], t]) for l in L if lines_df.BarIni[l] == n) -
    sum(b_susceptance[l]*(theta[lines_df.BarFin[l], t] - theta[lines_df.BarIni[l], t]) for l in L if lines_df.BarFin[l] == n) == demand[n, t])

# Límites de generación de cada generador
for g in G, t in T
    @constraint(model, pot_min[g] <= p[g, t] <= pot_max[g])
end

# Capacidad de las líneas de transmisión
for l in L, t in T
    @constraint(model, b_susceptance[l]*(theta[lines_df.BarIni[l], t] - theta[lines_df.BarFin[l], t]) <= line_max[l])
end

# Restricciones de rampa
for g in G, t in 2:length(T)
    @constraint(model, -ramp[g] <= p[g, t] - p[g, t-1] <= ramp[g])
end

# Fijar el ángulo del nodo slack (nodo 1) a 0 para todos los periodos
for t in T
    @constraint(model, theta[1, t] == 0)
end

# Función objetivo: minimizar el costo total
@objective(model, Min, sum(gen_cost[g] * p[g, t] for g in G for t in T))

# Resolver el modelo
optimize!(model)

# Imprimir el valor de la función objetivo y la solución
valor_objetivo = objective_value(model)
println("Valor de la función objetivo: ", valor_objetivo*pot_base)

# Extraer e imprimir la solución
solucion_potencia = value.(p)*pot_base
solucion_angulos = value.(theta)
println("Potencia generada por generador y tiempo:")
println(solucion_potencia)
println("Ángulo del voltaje en nodo y tiempo:")
println(solucion_angulos)

# Imprimir los precios sombra de la restricción de demanda
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
XLSX.openxlsx("precios_sombra_p1.xlsx", mode="w") do xf
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