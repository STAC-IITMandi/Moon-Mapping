import xml.etree.ElementTree as ET
from shapely.geometry import Polygon
import cv2
import numpy as np
import pandas as pd
import os
import matplotlib.pyplot as plt
from shapely.geometry import Polygon
from matplotlib.patches import Polygon as MatplotlibPolygon
import geopandas as gpd

def file_coords(xml_file_path = r'E:\ISRO PS-Transformer\DataSet\OHRC\ch2_ohr_nrp_20200229T0938004033_d_img_d32\data\raw\20200229\ch2_ohr_nrp_20200229T0938004033_d_img_d32.xml'):
    tree = ET.parse(xml_file_path)
    root = tree.getroot()

    # Define the namespace dictionary
    namespace = {
        'isda': 'https://isda.issdc.gov.in/pds4/isda/v1',
    }

    # Function to extract latitude and longitude values
    def extract_coordinates(element):
        coordinates = element.find('.//isda:System_Level_Coordinates', namespace)
        upper_left_latitude = coordinates.find('./isda:upper_left_latitude', namespace).text
        upper_left_longitude = coordinates.find('./isda:upper_left_longitude', namespace).text
        
        upper_right_latitude = coordinates.find('./isda:upper_right_latitude', namespace).text
        upper_right_longitude = coordinates.find('./isda:upper_right_longitude', namespace).text
        
        lower_left_latitude = coordinates.find('./isda:lower_left_latitude', namespace).text
        lower_left_longitude = coordinates.find('./isda:lower_left_longitude', namespace).text
        
        lower_right_latitude = coordinates.find('./isda:lower_right_latitude', namespace).text
        lower_right_longitude = coordinates.find('./isda:lower_right_longitude', namespace).text    
        
        return [(lower_left_longitude, lower_left_latitude), (lower_right_longitude, lower_right_latitude), (upper_right_longitude, upper_right_latitude), (upper_left_longitude, upper_left_latitude)]

    # Extract coordinates from the XML
    coordinates = extract_coordinates(root)
    # Print the results
    return coordinates



def cut_out_quadrilateral(image_path, output_path, src_coordinates, dst_coordinates):
    # Read the image
    image = cv2.imread(image_path)
    
    # Convert the coordinates to NumPy arrays
    src_pts = np.array(src_coordinates, dtype=np.float32)
    dst_pts = np.array(dst_coordinates, dtype=np.float32)

    # Calculate the perspective transformation matrix
    perspective_matrix = cv2.getPerspectiveTransform(src_pts, dst_pts)

    # Apply the perspective transformation to obtain the cut-out region
    warped_image = cv2.warpPerspective(image, perspective_matrix, (image.shape[1], image.shape[0]))

    # Save the cut-out region to a new image file
    cv2.imwrite(output_path, warped_image)

files1={}
files2={}

def iterate_files(base_dir):
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if file.endswith('.xml'):
                file_path = os.path.join(root, file)
                return file_path
                
def iterate_images(base_dir):
    for root, dirs, files in os.walk(base_dir):
        for file in files:
            if file.endswith('.png'):
                file_path = os.path.join(root, file)
                return file_path
            
def browse_folders(base_dir, data):
    for entry in os.scandir(base_dir):
        if entry.is_dir():
            folder_name = entry.name
            data[folder_name] = file_coords(iterate_files(os.path.join(base_dir, folder_name, "data")))
            


# Function to find XML files and generate PNG file link
def parse_xml_and_get_png(xml_file_path, base_dir):
    # Extracting information from XML file path
    xml_filename = os.path.basename(xml_file_path)
    date_folder = os.path.basename(os.path.dirname(xml_file_path))
    channel = xml_filename.split('_')[0]

    # Creating corresponding PNG file path
    png_filename = xml_filename.replace('d_img', 'b_brw').replace('.xml', '.png')
    png_file_path = os.path.join(base_dir, 'browse', 'calibrated', date_folder, png_filename)

    return png_file_path

# Function to parse all XML files under the 'data\calibrated' directory and create a dictionary
def parse_all_xml_files(directory, base_dir):
    xml_files_dict = {}
    for root, dirs, files in os.walk(os.path.join(base_dir, 'data', 'calibrated')):
        for file in files:
            if file.endswith('.xml'):
                xml_file_path = os.path.join(root, file)
                png_file_path = parse_xml_and_get_png(xml_file_path, base_dir)
                xml_files_dict[file] = [file_coords(xml_file_path), png_file_path]

    return xml_files_dict

def find_common_area(poly1_coords, poly2_coords):
    # Create GeoDataFrame with the provided coordinates and custom CRS for the Moon
    moon_crs = "+proj=longlat +a=1737400 +b=1737400 +no_defs"  # Example CRS for the Moon
    poly1 = Polygon(poly1_coords)
    poly2 = Polygon(poly2_coords)
        
    gdf = gpd.GeoDataFrame(geometry=[poly1, poly2], crs=moon_crs)

    # Find the intersection of the two polygons
    intersection = gdf.intersection(gdf.iloc[0].geometry)

    # Check if there is a common area
    if intersection.is_empty:
        print("There is no common area between the two polygons.")
        return None

    # Handle both Polygon and MultiPolygon cases
    if intersection.geom_type == 'Polygon':
        common_area_coords = list(intersection.exterior.coords)
    elif intersection.geom_type == 'MultiPolygon':
        common_area_coords = [list(p.exterior.coords) for p in intersection.geoms][0]
    else:
        print("Unexpected geometry type.")
        return None

    return common_area_coords

base_dir = r'G:\My Drive\Moon Mapping\DataSet\OHRC\files'
xml_files_dict_ohrc = parse_all_xml_files(os.path.join(base_dir, 'data', 'calibrated'), base_dir)


coor_csv = pd.read_csv(r"G:\My Drive\Moon Mapping\DataSet\TMC\coordinates.csv")
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
                
                tmc_files[file] = [[(lower_left_longitude, lower_left_latitude), (lower_right_longitude, lower_right_latitude), (upper_right_longitude, upper_right_latitude), (upper_left_longitude, upper_left_latitude)], file_path]

    return tmc_files

fig, ax = plt.subplots()
xml_files_dict_tmc = iterate_tmc(r'G:\My Drive\Moon Mapping\DataSet\TMC', coor_csv)

output_path1 = r'G:\My Drive\Moon Mapping\DataSet\Test'
output_path2 = r'G:\My Drive\Moon Mapping\DataSet\GT'

iterator = 0
it = 0
for image_tmc in xml_files_dict_tmc:
    for image_ohrc in xml_files_dict_ohrc:
        if(not (np.isnan(xml_files_dict_tmc[image_tmc][0])).any()):
            intersect = find_common_area(xml_files_dict_tmc[image_tmc][0], xml_files_dict_ohrc[image_ohrc][0])
            it += 1
            if(intersect is not None and len(intersect)==5):
                print(intersect)
                intersect.pop()
                # cut_out_quadrilateral(xml_files_dict_tmc[image_tmc][1], output_path1 + rf'\{iterator}_{image_tmc[:-4]}.png', xml_files_dict_tmc[image_tmc][0], intersect)
                # cut_out_quadrilateral(xml_files_dict_ohrc[image_ohrc][1], output_path2 + rf'\{iterator}_{image_ohrc[:-4]}.png', xml_files_dict_ohrc[image_ohrc][0], intersect)
                iterator += 1
        else:
            continue

plt.tight_layout()
plt.show()