import cv2
import os
import numpy as np
from geographiclib.geodesic import Geodesic


def get_pix_coor(carr, query, shape):
    # Define the Moon's ellipsoid parameters
    moon_ellipsoid = Geodesic.WGS84
    moon_ellipsoid.a = 1738.1  # Semi-major axis
    moon_ellipsoid.f = 0.0     # Flattening (since it's a sphere)
    
    ref_line = moon_ellipsoid.InverseLine(carr['ult'],carr['ulg'],carr['llt'],carr['llg'])
    
    conv_fact = max(shape)/ref_line.s13
    print("conversion Factor: ", conv_fact)
    
    target_line = moon_ellipsoid.InverseLine(carr['ult'],carr['ulg'], query[0], query[1])
    
    angle = target_line.azi1 - ref_line.azi1
    
    target_refl = moon_ellipsoid.Direct(carr['ult'], carr['ulg'], angle, target_line.s13)
    
    perp_line = moon_ellipsoid.InverseLine(target_refl['lat2'], target_refl['lon2'], query[0], query[1])

    perp_base = perp_line.Position(perp_line.s13/2)

    ref_int = moon_ellipsoid.InverseLine(carr['ult'], carr['ulg'], perp_base['lat2'], perp_base['lon2'])
    
    x = conv_fact*ref_int.s13
    y = conv_fact*perp_line.s13/2
    
    return [x,y]

def transform_img(image, vertices):
    # Create a black mask with the same size as the image
    mask = np.zeros_like(image)
    # Fill the polygon in the mask
    cv2.fillPoly(mask, [vertices], color=(255, 255, 255))
    # Bitwise AND operation to get the cropped region
    result = cv2.bitwise_and(image, mask)
    
    return result
    
def crop_img(image, vertices):
    # Define the source and destination corner coordinates
    print(vertices) #Debug Statement
    src_corners = np.float32([[0, 0], [0, image.shape[0]], [image.shape[1], 0], [image.shape[1], image.shape[0]]])
    # [[ullong, ullat], [lllong,lllat], [urlong, urlat], [lrlong, lrlat]]
    dst_corners = np.float32(vertices)

    # Calculate the perspective transformation matrix
    matrix = cv2.getPerspectiveTransform(src_corners, dst_corners)
    print(vertices) #Debug Statement
    # Apply the transformation
    size = int(max(max(vertices)) - min(min(vertices)))
    print((size))
    result = cv2.warpPerspective(image, matrix, (size, size))    
    
    return result

def main():
    out_dir = ""
    imgpath = 'ch2_tmc_ncn_20211113T0855227665_b_brw_d18.png'
    img = cv2.imread(imgpath)
    imgarray = img[:,:,1]
    h,w = imgarray.shape

    coor1 = {'llt': 0.66698,
            'llg': -163.334125,
            'lrt': 0.714117,
            'lrg': -162.786999,
            'ult': 30.230757,
            'ulg': -163.483959,
            'urt': 30.282345,
            'urg': -162.809506}

    # Define the Moon's ellipsoid parameters
    moon_ellipsoid = Geodesic.WGS84
    moon_ellipsoid.a = 1738.1  # Semi-major axis
    moon_ellipsoid.f = 0.0     # Flattening (since it's a sphere)

    # l = moon_ellipsoid.InverseLine(coor1['ult'],coor1['ulg'],coor1['llt'],coor1['llg'])
    # r = moon_ellipsoid.InverseLine(coor1['urt'],coor1['urg'],coor1['lrt'],coor1['lrg'])

    carr = {'llt': 5,
            'llg': -3,
            'lrt': 0,
            'lrg': 0,
            'ult': 30,
            'ulg': 10,
            'urt': 25,
            'urg': 12}

    query = (10,0)

    shape = (10000,500)

    ref_line = moon_ellipsoid.InverseLine(carr['ult'],carr['ulg'],carr['llt'],carr['llg'])

    conv_fact = max(shape)/ref_line.s13

    target_line = moon_ellipsoid.InverseLine(carr['ult'],carr['ulg'], query[0], query[1])

    angle = target_line.azi1 - ref_line.azi1

    target_refl = moon_ellipsoid.Direct(carr['ult'], carr['ulg'], (target_line.azi1-(2*angle)), target_line.s13)

    perp_line = moon_ellipsoid.InverseLine(target_refl['lat2'], target_refl['lon2'], query[0], query[1])

    perp_base = perp_line.Position(perp_line.s13/2)

    ref_int = moon_ellipsoid.InverseLine(carr['ult'], carr['ulg'], perp_base['lat2'], perp_base['lon2'])

    x = conv_fact*ref_int.s13
    y = conv_fact*perp_line.s13/2


if __name__ == '__main__':
    main()
