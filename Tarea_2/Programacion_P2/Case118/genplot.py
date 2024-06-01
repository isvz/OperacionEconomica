import pandas as pd
import matplotlib.pyplot as plt

# Cargar datos desde el archivo CSV
df = pd.read_csv('estado_generadores99.csv')

# Convertir los datos a formato adecuado para gráfico de barras
generadores = df['Generador']
horas = df.columns[1:]

# Crear una figura y un eje
fig, ax = plt.subplots(figsize=(12, 8))

# Colores para los estados ON y OFF
colors = {0: 'red', 1: 'green'}

# Agregar barras para cada generador y hora
for idx, generador in enumerate(generadores):
    estados = df.iloc[idx, 1:].astype(int)
    for i, estado in enumerate(estados):
        ax.bar(i + 1, 1, bottom=idx, color=colors[estado])

# Etiquetas y leyenda
ax.set_yticks(range(len(generadores)))
ax.set_yticklabels(generadores)
ax.set_xticks(range(1, 25))
ax.set_xticklabels(horas)
ax.set_xlabel('Hora del día')
ax.set_ylabel('Generador')
ax.set_title('Estado ON/OFF de los Generadores a lo Largo del Día con intervalo 99')
ax.grid(True)

# Crear leyenda personalizada
import matplotlib.patches as mpatches
on_patch = mpatches.Patch(color='green', label='ON')
off_patch = mpatches.Patch(color='red', label='OFF')
plt.legend(handles=[on_patch, off_patch], loc='upper right')

# Guardar el gráfico como una imagen
plt.savefig('estado_generadores.png')

# Mostrar el gráfico
plt.show()
