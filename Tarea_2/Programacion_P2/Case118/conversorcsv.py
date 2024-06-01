import pandas as pd

def convertir_excel_a_csv(excel_path, csv_path):
    # Leer el archivo de Excel
    df = pd.read_excel(excel_path)
    print(df)
    df.rename(columns={df.columns[0]: 'Generador'}, inplace=True)
    df.columns = ['Generador'] + [str(i) for i in range(1, 25)]
    df.to_csv(csv_path, index=False)


excel_path = 'estado_generadores.xlsx'
csv_path = 'estado_generadores90.csv'

convertir_excel_a_csv(excel_path, csv_path)

print(f"Archivo convertido y guardado como {csv_path}")
