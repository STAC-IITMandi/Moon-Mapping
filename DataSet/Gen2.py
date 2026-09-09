# %%
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
from geographiclib.geodesic import Geodesic
from tmc_break import get_pix_coor, crop_img
from spherical_geometry import graph, great_circle_arc, polygon, vector

# %%
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

def SphericalPoly(img_corners):
  coordinates_xyz = [vector.normalize_vector(vector.lonlat_to_vector(float(lon), float(lat), degrees=True)) for lon, lat in img_corners]
  inside_point = great_circle_arc.midpoint(coordinates_xyz[0], coordinates_xyz[2])
  poly = polygon.SingleSphericalPolygon(coordinates_xyz, inside=inside_point)
  return poly

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
    gdf.plot()
    # Find the intersection of the two polygons
    intersection = gdf.geometry.iloc[0].intersection(gdf.geometry.iloc[1])

    # Check if there is a common area
    if intersection.geom_type == 'MultiPolygon':
        common_area_coords = []
        for polygon in intersection:
            common_area_coords.extend(list(polygon.exterior.coords))
    else:
        common_area_coords = list(intersection.exterior.coords)


    return common_area_coords

def main():
  # %%
  intersection = pd.read_csv(r"G:\My Drive\Moon Mapping\DataSet\file1 (3).csv")

  # %%
  for it in range(3):
      input_string = intersection['Tmc_Corners'].iloc[it]
      tmc_coords_lon = eval(input_string[1:-1].split('array')[1][:-2])
      tmc_coords_lat = eval(input_string[1:-1].split('array')[2])
      
      tmc_coords={}
      keys = ['llt','llg','lrt','lrg','urt','urg','ult','ulg']
      
      
      for i in range(len(tmc_coords_lat)-1):
          tmc_coords[keys[2*i]] = tmc_coords_lat[i]
          tmc_coords[keys[2*i+1]] = tmc_coords_lon[i]
          
      input_string = intersection['Tmc_Corners'].iloc[it]
      ohrc_coords_lon = eval(input_string[1:-1].split('array')[1][:-2])
      ohrc_coords_lat = eval(input_string[1:-1].split('array')[2])
      
      ohrc_coords={}
      for i in range(len(ohrc_coords_lat)-1):
          ohrc_coords[keys[2*i]] = ohrc_coords_lat[i]
          ohrc_coords[keys[2*i+1]] = ohrc_coords_lon[i]
          
      input_string = intersection['Tmc_Corners'].iloc[it]
      inter_coords_lon = eval(input_string[1:-1].split('array')[1][:-2])
      inter_coords_lat = eval(input_string[1:-1].split('array')[2])
      
      inter_coords=[]
      for i in range(len(inter_coords_lat)-1):
          inter_coords.append([inter_coords_lon[i], inter_coords_lat[i]])
      
      tmc_image_file = intersection['Tmc_File_Location'].iloc[0]
      ohrc_image_file = intersection['Ohrc_File_Location'].iloc[0]
    
      tmc_img = cv2.imread(tmc_image_file)
      pix_inter_coor = []
      for geo_coor in inter_coords:
          pix_coor = get_pix_coor(tmc_coords, geo_coor, tmc_img.shape)
          pix_inter_coor.append(pix_coor)
      
      cropped_tmc = crop_img(tmc_img, pix_inter_coor)
      
      cv2.imwrite(rf'Test\{it}.png', cropped_tmc)
      
if __name__ == '__main__':
  main()