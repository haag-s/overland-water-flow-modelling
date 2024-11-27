#!/bin/bash
# Initalise modules
module use /dss/dsstbyfs01/pn56su/pn56su-dss-0020/usr/share/modules/files/
module load charliecloud
# **********************************************************
# List of raster files to import
declare -A RASTERS_TO_IMPORT=(
["dem1-id_subset.tif"]="dgm"
["dem1-id_dx_subset.tif"]="dx"
["dem1-id_dy_subset.tif"]="dy"
["radolan_excess_1m_illdorf_subset.tif"]="rain"
["mannings_n_1m_bilinear_subset.tif"]="manningsn"
)
# Parameter for r.sim.water
NITERATIONS=10
OUTPUT_STEP=2
DIFFUSION_COEFF=0.8
HMAX=0.3
HALPHA=4
HBETA=0.5
# Output file names
OUTPUT_DEPTH_NAME="depth_subset_n50.tif"
OUTPUT_ERROR_NAME="error_subset_n50.tif"
OUTPUT_DISCHARGE_NAME="discharge_subset_n50.tif"
# **********************************************************
# Input directories and container path
DIR="/dss/dsshome1/0A/di38fec/Simulation_Burkheim"
INPUT_DIR="$DIR/input"
OUTPUT_DIR="$DIR/output"
CHARLIECLOUD_IMAGE="$DIR/charliecloud_image.sqfs"
LOCATION_NAME="my_location"
MAPSET_NAME="PERMANENT"
LOCATION_PATH="$DIR/location"
# Check directories
check_directory() {
	if [[ ! -d "$1" ]]; then
	echo "Directory does not exist: $1"
	exit 1
	fi
}
check_directory "$INPUT_DIR"
check_directory "$OUTPUT_DIR"
check_directory "$LOCATION_PATH"
# Delete old location, if available
if [[ -d "$LOCATION_PATH/$LOCATION_NAME" ]]; then
echo "Deleting existing location: $LOCATION_NAME"
rm -rf "$LOCATION_PATH/$LOCATION_NAME"
fi
# Dynamic creation of grass_commands.sh
DYNAMIC_SCRIPT="$DIR/grass_commands.sh"
# Convert the RASTER_TO_IMPORT into a variable
RASTERS_TO_IMPORT_STRING=""
for input_file in "${!RASTERS_TO_IMPORT[@]}"; do
output_file="${RASTERS_TO_IMPORT[$input_file]}"
RASTERS_TO_IMPORT_STRING+="$input_file:$output_file "
done
cat << 'EOF' > "$DYNAMIC_SCRIPT"
#!/bin/bash
# Input directory and parameters
INPUT_DIR="$1"
LOCATION_PATH="$2"
LOCATION_NAME="$3"
MAPSET_NAME="$4"
NITERATIONS="$5"
OUTPUT_STEP="$6"
OUTPUT_DIR="$7"
OUTPUT_DEPTH_NAME="$8"
IFS=' ' read -r -a RASTERS_TO_IMPORT_ARRAY <<< "$9"
OUTPUT_ERROR_NAME="${10}"
OUTPUT_DISCHARGE_NAME="${11}"
DIFFUSION_COEFF="${12}"
HMAX="${13}"
HALPHA="${14}"
HBETA="${15}"
# Import rasters
echo "-----------------------------------------"
echo "Import raster files"
echo "---------------------"
for raster_pair in "${RASTERS_TO_IMPORT_ARRAY[@]}"; do
IFS=':' read input_file output_file <<< "$raster_pair"
grass "$LOCATION_PATH/$LOCATION_NAME/$MAPSET_NAME" --exec r.import input="$INPUT_DIR/
$input_file" output="$output_file" --overwrite
echo "Importiert: $input_file als $output_file"
done
# Show list of imported raster maps
echo "---------------------"
echo "List of imported raster maps:"
grass "$LOCATION_PATH/$LOCATION_NAME/$MAPSET_NAME" --exec g.list type=raster
echo "---------------------"
echo "Import complete"
echo "-----------------------------------------"
echo "Start r.sim.water"
echo "---------------------"
echo "Selected parameters for simulation:"
echo "NIterations: $NITERATIONS"
echo "Diffusion_Coeff: $DIFFUSION_COEFF"
echo "Hmax: $HMAX"
echo "Halpha: $HALPHA"
echo "Hbeta: $HBETA"
echo "---------------------"
# Start time measurement
START_TIME=$(date +%s)
# Executing the r.sim.water command
grass "$LOCATION_PATH/$LOCATION_NAME/$MAPSET_NAME" --exec r.sim.water elevation=
"dgm@PERMANENT" \
dx="dx@PERMANENT" dy="dy@PERMANENT" \
rain="rain@PERMANENT" man="manningsn@PERMANENT" depth="depth" \
discharge="discharge" error="error" \
niterations="$NITERATIONS" output_step="$OUTPUT_STEP" \
diffusion_coeff="$DIFFUSION_COEFF" hmax="$HMAX" halpha="$HALPHA" hbeta="$HBETA"
# Stop time measurement
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
# Conversion to minutes and seconds
DURATION_MINUTES=$((DURATION / 60))
DURATION_SECONDS=$((DURATION % 60))
echo "---------------------"
echo "Simulation completed in $DURATION_MINUTES minutes and $DURATION_SECONDS seconds."
echo "-----------------------------------------"
echo "Export simulated water depth, error and discharge raster as GeoTiff"
echo "---------------------"
grass "$LOCATION_PATH/$LOCATION_NAME/$MAPSET_NAME" --exec r.out.gdal input=depth
output="$OUTPUT_DIR/$OUTPUT_DEPTH_NAME" format=GTiff nodata=-999 --overwrite -c
grass "$LOCATION_PATH/$LOCATION_NAME/$MAPSET_NAME" --exec r.out.gdal input=error
output="$OUTPUT_DIR/$OUTPUT_ERROR_NAME" format=GTiff nodata=-999 --overwrite -c
grass "$LOCATION_PATH/$LOCATION_NAME/$MAPSET_NAME" --exec r.out.gdal input=discharge
output="$OUTPUT_DIR/$OUTPUT_DISCHARGE_NAME" format=GTiff nodata=-999 --overwrite -c
echo "---------------------"
echo "Export complete"
echo "-----------------------------------------"
EOF
# Set execution rights for the dynamically created script
chmod +x "$DYNAMIC_SCRIPT"
# Create GRASS GIS location and execute commands
ch-run --home -b "/dss/.:/dss/" \
"$CHARLIECLOUD_IMAGE" -- bash -c "
# Create GRASS Location
grass -c $INPUT_DIR/dem1-id_subset.tif $LOCATION_PATH/$LOCATION_NAME -e
echo 'Location \"$LOCATION_NAME\" created.'
# Execute commands script
bash $DYNAMIC_SCRIPT $INPUT_DIR $LOCATION_PATH $LOCATION_NAME $MAPSET_NAME 
$NITERATIONS $OUTPUT_STEP $OUTPUT_DIR $OUTPUT_DEPTH_NAME \"$RASTERS_TO_IMPORT_STRING\"
$OUTPUT_ERROR_NAME $OUTPUT_DISCHARGE_NAME $DIFFUSION_COEFF $HMAX $HALPHA $HBETA
# Close bash session
exit
"
echo "Container and GRASS GIS closed."