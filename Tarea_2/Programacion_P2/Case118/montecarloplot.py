import pandas as pd
import numpy as np
from scipy import stats
import matplotlib.pyplot as plt

def simular_montecarlo(df, kappa_wind, kappa_solar, num_scenarios):
    montecarlo = []
    gen = df.iloc[:, 0]  
    for i in range(num_scenarios):
        dataescenario = {}

        generadores = list(gen[:-4]) + ['Total Wind', 'Total Solar', 'Total Renovable']  # Excluye los últimos cuatro elementos no generadores

        dataescenario["Gen/Hour"] = generadores

        for t in range(24):
            gen_t = []
            total_wind = 0
            total_solar = 0
            for j in range(len(generadores) - 3):  
                Xt = df.iloc[j, t + 1]  
                sigmat = kappa_wind[t] * Xt if "WindFarm" in generadores[j] else kappa_solar[t] * Xt
                e_t = np.random.normal(0, sigmat)
                Xi = np.round(np.maximum(e_t + Xt, 0), 3)
                gen_t.append(Xi)
                if "WindFarm" in generadores[j]:
                    total_wind += Xi
                elif "SolarFarm" in generadores[j]:
                    total_solar += Xi

            gen_t.append(total_wind)
            gen_t.append(total_solar)
            gen_t.append(total_wind + total_solar)
            
            dataescenario[f"{t + 1}"] = gen_t

        dataframeescenario = pd.DataFrame.from_dict(dataescenario, orient='index').transpose() 
        montecarlo.append(dataframeescenario)

    return montecarlo

def calcular_promedios_intervalos(montecarlo, columna):
    num_horas = 24
    promedios = []
    confianza_90 = []
    confianza_99 = []

    for t in range(1, num_horas + 1):
        datos_hora = [df.loc[:, str(t)][df['Gen/Hour'] == columna].values for df in montecarlo]
        datos_hora = np.concatenate(datos_hora)  

        # Calcular promedio
        promedio = np.mean(datos_hora)
        promedios.append(promedio)

        # Calcular intervalos de confianza
        se = stats.sem(datos_hora)  # Error estándar de la media
        ic_90 = se * stats.t.ppf((1 + 0.90) / 2., len(datos_hora)-1)  # T-student para 90%  
        ic_99 = se * stats.t.ppf((1 + 0.99) / 2., len(datos_hora)-1)  # T-student para 99%


        confianza_90.append((promedio - ic_90, promedio + ic_90, promedio))
        confianza_99.append((promedio - ic_99, promedio + ic_99, promedio))


    return promedios, confianza_90, confianza_99




def graficar_resultados(promedios, intervalo_90, intervalo_99, titulo, nombre_archivo):
    horas = list(range(1, 25))
    lower_90, upper_90, _ = zip(*intervalo_90)
    lower_99, upper_99, _ = zip(*intervalo_99)

    plt.figure(figsize=(10, 6))
    plt.plot(horas, promedios, label='Promedio', color='black')
    plt.fill_between(horas, lower_90, upper_90, color='blue', alpha=0.1, label='Intervalo de Confianza 90%')
    plt.fill_between(horas, lower_99, upper_99, color='red', alpha=0.1, label='Intervalo de Confianza 99%')
    plt.xlabel('Hora del día')
    plt.ylabel(f'{titulo} (kWh)')
    plt.title(f'Promedio de {titulo} y Intervalos de Confianza')
    plt.legend()
    plt.grid(True)
    plt.savefig(nombre_archivo)
    plt.show()





# Datos de entrada y configuración
df = pd.read_csv('Renewables.csv')  
num_scenarios = 100
kappa_wind = np.linspace(0.147, 0.3092, 24)  
kappa_solar = np.linspace(0.1020, 0.1402, 24)

# Simulación de Monte Carlo
simulated_data = simular_montecarlo(df, kappa_wind, kappa_solar, num_scenarios)
promedios, intervalo_90, intervalo_99 = calcular_promedios_intervalos(simulated_data, 'Total Solar')
graficar_resultados(promedios, intervalo_90, intervalo_99, "Generación Solar", "generacion_solar.png")

promedios, intervalo_90, intervalo_99 = calcular_promedios_intervalos(simulated_data, 'Total Wind')
graficar_resultados(promedios, intervalo_90, intervalo_99, "Generación Eólica", "generacion_eolica.png")

promedios, intervalo_90, intervalo_99 = calcular_promedios_intervalos(simulated_data, 'Total Renovable')
graficar_resultados(promedios, intervalo_90, intervalo_99, "Generación Total", "generacion_total.png")


for idx, df in enumerate(simulated_data):
    df.to_csv(f'simulation\simulated_data_{idx}.csv', index=False)


# # Crear DataFrames desde los intervalos
df_intervalo_90 = pd.DataFrame(intervalo_90, columns=['Lower', 'Upper', 'Prom'])
df_intervalo_99 = pd.DataFrame(intervalo_99, columns=['Lower', 'Upper', 'Prom'])

# # Exportar a CSV
df_intervalo_90.to_csv('simulation\intervalo_90_renewable.csv', index=False)
df_intervalo_99.to_csv('simulation\intervalo_99_renewable.csv', index=False)
