#!bnxsr/bin/env python
import requests
from bs4 import BeautifulSoup
from datetime import datetime, timedelta
import os
import fnmatch

# Define global variables
# --------------------------------

outdir = "/srv/shiny-server/harvest/appdata/noaa_star/"

if not os.path.exists(outdir):
   os.makedirs(outdir)

os.chdir(outdir)

# Retrieve NOAA STAR Data 
# --------------------------------

def get_url_paths(url, ext='', params={}):
    response = requests.get(url, params=params)
    if response.ok:
        response_text = response.text
    else:
        return response.raise_for_status()
    soup = BeautifulSoup(response_text, 'html.parser')
    parent = [url + node.get('href') for node in soup.find_all('a') if node.get('href').endswith(ext)]
    return parent

url = 'https://www.star.nesdis.noaa.gov/pub/smcd/emb/bobk/Enterprise_Global/'
ext = 'nc'
result = get_url_paths(url, ext)

filtered = [x for x in result if x.startswith("https://www.star.nesdis.noaa.gov/pub/smcd/emb/bobk/Enterprise_Global/RRQPE-001HR-GLB_v1r1_blend_s")]

tmp = [i.lstrip("https://www.star.nesdis.noaa.gov/pub/smcd/emb/bobk/Enterprise_Global/RRQPE-001HR-GLB_v1r1_blend_s") for i in filtered]

# Remove all file strings in tmp which include *HR* in the file name (no additioanl temporal averages)


filedates = [i.rstrip(".nc") for i in tmp]
del filedates[-1]

for i in filtered:
    tmp = i.lstrip("https://www.star.nesdis.noaa.gov/pub/smcd/emb/bobk/Enterprise_Global/RRQPE-001HR-GLB_v1r1_blend_s")
    filedate = tmp.rstrip(".nc")
    checkfiles = "noaa_star_precip_" + filedate + ".nc"
    out = len(fnmatch.filter(os.listdir(outdir), checkfiles))
    if out == 1:
        print("Skipping date " + filedate + ", it has already been retrieved ...")
    else:
        print("Downloading file noaa_star_precip_" + filedate + ".nc ...")
        response = requests.get(i)
        open("noaa_star_precip_" + filedate + ".nc","wb").write(response.content)

# Delete files older than x days
# --------------------------------

target_date = datetime.today() - timedelta(days = 4)
file_list = os.listdir(outdir)

for f in file_list:
    file_date_str = f[17:25]  # Change the split character as needed
    print(file_date_str)
    if len(file_date_str) > 7: 
        file_date = datetime.strptime(file_date_str, '%Y%m%d')
    
    # Compare the file date with the target date and remove if older
    if file_date < target_date:
        file_path = os.path.join(outdir, f)
        os.remove(file_path)
        print(f"Removed file: {file_path}")
    

print("Finished NOAA retrieval and clean-up")
