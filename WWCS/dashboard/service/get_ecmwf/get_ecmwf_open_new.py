from datetime import datetime, timedelta
import os
import re
import glob
import shutil
import mysql.connector
import pandas as pd
import yaml
from cdo import Cdo
from ecmwf.opendata import Client
from common import USERNAME, PASSWORD

cdo = Cdo()

# ---------------------------------------------------------------------
# Load configuration
# ---------------------------------------------------------------------
with open('/home/wwcs/wwcs/WWCS/config.yaml', 'r') as file:
    config = yaml.safe_load(file)

train_period = config['train_period']
forecast_days = config['forecast_days']
maxlat = config['maxlat']
minlat = config['minlat']
maxlon = config['maxlon']
minlon = config['minlon']
total_days = train_period + forecast_days

# ---------------------------------------------------------------------
# Cleanup old files (>60 days)
# ---------------------------------------------------------------------
directory_path = "/srv/shiny-server/dashboard/ifsdata"
date_pattern = r'(\d{4})-(\d{2})-(\d{2})'
two_months_ago = datetime.now() - timedelta(days=60)

for filename in os.listdir(directory_path):
    match = re.search(date_pattern, filename)
    if match:
        year, month, day = map(int, match.groups())
        try:
            if datetime(year, month, day) < two_months_ago:
                os.remove(os.path.join(directory_path, filename))
                print(f"Deleted old file: {filename}")
        except ValueError:
            print(f"Invalid date in filename: {filename}")

# ---------------------------------------------------------------------
# Setup variables
# ---------------------------------------------------------------------
outdir = "/srv/shiny-server/dashboard/ifsdata"
tmpdir = os.path.join(outdir, "tmp")
os.makedirs(tmpdir, exist_ok=True)

client = Client(source="ecmwf")
steps = list(range(0, 243, 3))  # 0–240 hours

datelist = [d.strftime("%Y-%m-%d") for d in pd.date_range(
    datetime.today() - timedelta(days=total_days), datetime.today())]

# ---------------------------------------------------------------------
# Get station coordinates
# ---------------------------------------------------------------------
cnx = mysql.connector.connect(user=USERNAME, password=PASSWORD,
                              host='127.0.0.1', database='SitesHumans')
cursor = cnx.cursor(dictionary=True)
cursor.execute("SELECT siteID, latitude, longitude FROM Sites WHERE siteID NOT LIKE '%-S%'")
stations = cursor.fetchall()

# ---------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------
for dat in datelist:
    # Check if station files exist
    missing_files = []
    for s in stations:
        station_file = os.path.join(outdir, f"ifs_{s['siteID'].replace(' ', '')}_{dat}.nc")
        if not os.path.isfile(station_file):
            missing_files.append(s)

    if not missing_files:
        print(f"Skipping {dat}: all station files exist.")
        continue

    tj_file = os.path.join(outdir, f"tj_area_{dat}.nc")
    if not os.path.isfile(tj_file):
        print(f"\n=== Downloading ECMWF open data for {dat} ===")

        # Download control forecast
        for step in steps:
            target_cf = os.path.join(tmpdir, f"cf_step_{step}.grb")
            if not os.path.isfile(target_cf):
                client.retrieve(
                    date=dat,
                    time=0,
                    step=step,
                    stream="enfo",
                    levtype="sfc",
                    param="2t",
                    type="cf",
                    target=target_cf
                )

        # Download ensemble members (pf = perturbed forecasts)
        members = range(1, 51)  # ECMWF open data: 50 members
        for m in members:
            for step in steps:
                target_pf = os.path.join(tmpdir, f"pf{m:02d}_step_{step}.grb")
                if not os.path.isfile(target_pf):
                    client.retrieve(
                        date=dat,
                        time=0,
                        step=step,
                        stream="enfo",
                        levtype="sfc",
                        param="2t",
                        type="pf",
                        number=m,
                        target=target_pf
                    )

        # -----------------------------------------------------------------
        # Convert GRIBs to NetCDF and subset to area
        # -----------------------------------------------------------------
        print("Converting GRIB to NetCDF and cropping to area...")
        all_grbs = glob.glob(os.path.join(tmpdir, "*.grb"))
        nc_files = []

        for grb in all_grbs:
            nc_path = grb.replace(".grb", ".nc")
            nc_crop = grb.replace(".grb", "_tj.nc")
            if not os.path.isfile(nc_crop):
                cdo.copy(input=grb, output=nc_path, options='-t ecmwf -f nc')
                cdo.sellonlatbox(f"{minlon},{maxlon},{minlat},{maxlat}",
                                 input=nc_path, output=nc_crop)
            nc_files.append(nc_crop)

        # -----------------------------------------------------------------
        # Compute ensemble mean and standard deviation with CDO
        # -----------------------------------------------------------------
        print("Computing ensemble mean and standard deviation...")
        ensmean_file = os.path.join(tmpdir, "output_em.nc")
        ensstd_file = os.path.join(tmpdir, "output_es.nc")

        # Build lists of cropped files by type
        pf_files = sorted(glob.glob(os.path.join(tmpdir, "pf*_tj.nc")))
        cf_files = sorted(glob.glob(os.path.join(tmpdir, "cf*_tj.nc")))

        # Combine CF and PF files (control + members)
        ens_files = cf_files + pf_files

        # Merge time dimension first
        merged_ens = os.path.join(tmpdir, "merged_ens.nc")
        cdo.mergetime(input=" ".join(ens_files), output=merged_ens)

        # Compute mean and std over ensemble members
        cdo.ensmean(input=merged_ens, output=ensmean_file)
        cdo.ensstd(input=merged_ens, output=ensstd_file)

        # Rename variables
        renamed_em = os.path.join(tmpdir, "output_em_rn.nc")
        renamed_es = os.path.join(tmpdir, "output_es_rn.nc")
        cdo.chname(r"\2t,IFS_T_mea", input=ensmean_file, output=renamed_em)
        cdo.chname(r"\2t,IFS_T_std", input=ensstd_file, output=renamed_es)

        # Merge mean & std into single area file
        cdo.merge(input=f"{renamed_em} {renamed_es}", output=tj_file)
        print(f"Created {tj_file}")

        shutil.rmtree(tmpdir)
        os.mkdir(tmpdir)

    # ---------------------------------------------------------------------
    # Interpolate to stations using CDO (nearest neighbour)
    # ---------------------------------------------------------------------
    print(f"Interpolating {dat} to station points ...")
    for s in missing_files:
        fout = os.path.join(outdir, f"ifs_{s['siteID'].replace(' ', '')}_{dat}.nc")
        arg = f"lon={s['longitude']}_lat={s['latitude']}"
        cdo.remapnn(arg, input=tj_file, output=fout)
        print(f"  -> {fout}")

print("\nAll done!")
cnx.close()

