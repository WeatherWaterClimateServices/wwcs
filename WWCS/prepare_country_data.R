library(raster)

ROOT_DIR <- normalizePath(getwd(), mustWork = TRUE)
while (!file.exists(file.path(ROOT_DIR, ".git"))) {
  parent <- dirname(ROOT_DIR)
  if (parent == ROOT_DIR) break
  ROOT_DIR <- parent
}
source(file.path(ROOT_DIR, "WWCS/.Rprofile")) ## this reads in gadm0

## create directory if needed
boundary_dir <- file.path(ROOT_DIR, "WWCS/boundaries")
dir.create(boundary_dir, recursive=TRUE)

## download
system(paste0('wget -P ', boundary_dir, ' https://geodata.ucdavis.edu/gadm/gadm4.1/shp/gadm41_', gadm0 ,'_shp.zip'))
system(paste0('unzip -o ', boundary_dir, '/gadm41_', gadm0 ,'_shp.zip -d ',
              boundary_dir))

## process and save
country <- raster::shapefile(paste0(boundary_dir, '/gadm41_', gadm0, '_0.shp'))
wld <- raster::rasterToPolygons(raster(ncol = 1, nrow = 1, crs = proj4string(country)))
mask <- raster::erase(wld, country)
mask_sf <- sf::st_as_sf(mask, crs = st_crs(4326))
saveRDS(mask_sf, paste0(boundary_dir, '/mask.rds'))
