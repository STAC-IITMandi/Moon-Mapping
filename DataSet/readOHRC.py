import pds4_tools

# Open the .img file
file_path = r"G:\My Drive\Moon Mapping\DataSet\Misc\ch2_ohr_nrp_20220321T0525382085_d_img_hw1.xml"
label = pds4_tools.read(file_path)
image_data = pds4_tools.read(file_path)
# Access the label information
print("Label information:")
print(label)

# Access the image data as a NumPy array
print("Image data shape:", image_data.shape)

