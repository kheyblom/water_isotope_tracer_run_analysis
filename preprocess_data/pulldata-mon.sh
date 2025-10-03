#!/bin/bash 

input_directory_root=/glade/u/home/kheyblom/scratch/icesm_data/raw
output_directory_root=/glade/u/home/kheyblom/scratch/icesm_data/processed/mon

tag_bool=false

exps_in=("1850-iso-gridtags" \
         "historical-iso-r1" \
         "historical-iso-r2" \
         "historical-iso-r4" \
         "historical-iso-r4-tags" \
         "historical-iso-r4-tags_b" \
         "historical-iso-r5" \
         "historical-iso-r5-tags" \
         "historical-iso-r5-tags_b" \
         "rcp85_r1b" \
         "rcp85_r2" \
         "rcp85_r4" \
         "rcp85_r4-tags_b" \
         "rcp85_r4-tags_c" \
         "rcp85_r5" \
         "rcp85_r5-tags_b" \
         "rcp85_r5-tags_c")

exps_out=("iso-piControl-tag" \
          "iso-historical_r1" \
          "iso-historical_r2" \
          "iso-historical_r4" \
          "iso-historical_r4-tag-a" \
          "iso-historical_r4-tag-b" \
          "iso-historical_r5" \
          "iso-historical_r5-tag-a" \
          "iso-historical_r5-tag-b" \
          "iso-rcp85_r1" \
          "iso-rcp85_r2" \
          "iso-rcp85_r4" \
          "iso-rcp85_r4-tag-b" \
          "iso-rcp85_r4-tag-c" \
          "iso-rcp85_r5" \
          "iso-rcp85_r5-tag-b" \
          "iso-rcp85_r5-tag-c")

vars=("TS" "T" "U" "V" "OMEGA"
      "TREFHT" "TMQ"
      "Q" "HDOV" "H216OV" "H218OV" "H2OV"
      "PRECC" "PRECL"
      "PRECRC_HDOr" "PRECSC_HDOs" "PRECRL_HDOR" "PRECSL_HDOS"
      "PRECRC_H216Or" "PRECSC_H216Os" "PRECRL_H216OR" "PRECSL_H216OS"
      "PRECRC_H218Or" "PRECSC_H218Os" "PRECRL_H218OR" "PRECSL_H218OS"
      "PRECRC_H2Or" "PRECSC_H2Os" "PRECRL_H2OR" "PRECSL_H2OS"
      "QFLX" "QFLX_HDO" "QFLX_H216O" "QFLX_H218O" "QFLX_H2O")

if $tag_bool; then
        tags=("LAT85S"  "LAT75S"  "LAT65S"  "LAT55S"  "LAT45S"  "LAT35S"  "LAT25S"  "LAT15S"  "LAT05S"  "LAT05N"  "LAT15N"  "LAT25N"  "LAT35N"  "LAT45N"  "LAT55N"  "LAT65N"  "LAT75N"  "LAT85N"
              "LON05E"  "LON15E"  "LON25E"  "LON35E"  "LON45E"  "LON55E"  "LON65E"  "LON75E"  "LON85E"  "LON95E"  "LON105E" "LON115E" "LON125E" "LON135E" "LON145E" "LON155E" "LON165E" "LON175E"
              "LON185E" "LON195E" "LON205E" "LON215E" "LON225E" "LON235E" "LON245E" "LON255E" "LON265E" "LON275E" "LON285E" "LON295E" "LON305E" "LON315E" "LON325E" "LON335E" "LON345E" "LON355E")
        tags_pref=(""  "PRECRC_" "PRECRL_" "PRECSC_" "PRECSL_")
        tags_suff=("V" "r"       "R"       "s"       "S")
        for ((i=1; i<=${#tags_pref[@]}; i++)); do
                for tag in ${tags[*]}; do
                        vars+=(${tags_pref[i-1]}${tag}${tags_suff[i-1]})
                done
        done
fi

#cwd=$(pwd)

echo
for ((i=1; i<=${#exps_out[@]}; i++)); do
        echo "EXPERIMENT: "${exps_in[i-1]}
        out_dir=${output_directory_root}/${exps_out[i-1]}
        mkdir -p $out_dir
        in_dir=${input_directory_root}/${exps_in[i-1]}/cam/mon
        cd $in_dir
        for var in ${vars[*]}; do
                echo "  EXTRACTING: $var"
                ncrcat -O -v $var ${exps_in[i-1]}.cam.h0.*.nc ${out_dir}/${exps_out[i-1]}.${var}.mon.nc
        done
done
echo "COMPLETE"
echo
