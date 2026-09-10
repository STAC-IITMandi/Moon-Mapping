import os
import pandas as pd

coor_csv = pd.read_csv(r"TMC\coordinates.csv")

def iterate_tmc(base_dir, coor_csv):
    tmc_files = {}
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if file.endswith('.png'):
                file_path = os.path.join(root, file)
                filename =file.split('_b')[0]
                row = coor_csv[coor_csv['Filename'].str.startswith(filename)]
                upper_left_latitude = row['upper_left_latitude'].iloc[0]
                upper_left_longitude = row['upper_left_longitude'].iloc[0]
                
                upper_right_latitude = row['upper_right_latitude'].iloc[0]
                upper_right_longitude = row['upper_right_longitude'].iloc[0]
                
                lower_left_latitude = row['lower_left_latitude'].iloc[0]
                lower_left_longitude = row['lower_left_longitude'].iloc[0]
                
                lower_right_latitude = row['lower_right_latitude'].iloc[0]
                lower_right_longitude = row['lower_right_longitude'].iloc[0] 
                
                tmc_files[file] = [[(upper_left_latitude, upper_left_longitude), (upper_right_latitude, upper_right_longitude), (lower_left_latitude, lower_left_longitude), (lower_right_latitude, lower_right_longitude)], file_path]

    return tmc_files

print(iterate_tmc(r'G:\My Drive\Moon Mapping\DataSet\TMC', coor_csv))