#!/bin/bash
# Trims and time-lapses the raw Playwright recordings into the clips the video uses.
# usage: cut.sh RUN_A.webm RUN_B.webm RUN_C.webm OUT_DIR
#   RUN_A: baseline, chaos, SLO page.  RUN_B: exemplar hover and trace.  RUN_C: trace to logs.
# The second-offsets below come from each run's marks.json.
set -e
A=$1; B=$2; C=$3; P=$4
enc=(-c:v libx264 -crf 21 -preset medium -pix_fmt yuv420p -r 30 -an -movflags +faststart)
ffmpeg -v error -y -i "$A" -filter_complex "[0:v]trim=8:12.2,setpts=(PTS-STARTPTS)/2[a];[0:v]trim=12.2:70,setpts=(PTS-STARTPTS)/30[b];[0:v]trim=70:163.5,setpts=(PTS-STARTPTS)/14[c];[a][b][c]concat=n=3:v=1[v]" -map "[v]" "${enc[@]}" "$P/clip1-overview.mp4"
ffmpeg -v error -y -ss 164 -t 12 -i "$A" -filter_complex "[0:v]setpts=PTS/1.5[v]" -map "[v]" "${enc[@]}" "$P/clip2-slo.mp4"
ffmpeg -v error -y -ss 213.5 -t 10.5 -i "$B" -filter_complex "[0:v]setpts=PTS/1.25[v]" -map "[v]" "${enc[@]}" "$P/clip3-exemplar.mp4"
ffmpeg -v error -y -ss 224 -t 4.6 -i "$B" "${enc[@]}" /tmp/c4a.mp4
ffmpeg -v error -y -ss 52 -t 9.8 -i "$C" "${enc[@]}" /tmp/c4b.mp4
printf "file '/tmp/c4a.mp4'\nfile '/tmp/c4b.mp4'\n" > /tmp/c4.txt
ffmpeg -v error -y -f concat -safe 0 -i /tmp/c4.txt -filter_complex "[0:v]setpts=PTS/1.3[v]" -map "[v]" "${enc[@]}" "$P/clip4-trace.mp4"
for f in "$P"/clip*.mp4; do echo "$(basename "$f") $(ffprobe -v error -show_entries format=duration -of csv=p=0 "$f")"; done
