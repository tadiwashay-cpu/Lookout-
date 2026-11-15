#!/bin/bash
# Generate original animations from text with MoMask (Hugging Face Space
# MeYourHint/MoMask, a text-to-motion model). One BVH per take.
#   tools/gen_motion.sh OUT_DIR [takes]
# The move list is tools/moves.txt (Name|description). Convert the results
# with tools/convert_motion.py.
SPACE=https://meyourhint-momask.hf.space
OUT=$1; TAKES=${2:-2}; mkdir -p "$OUT"
while IFS='|' read -r NAME PROMPT; do
  [ -z "$NAME" ] && continue
  for K in $(seq 0 $((TAKES-1))); do
    DEST="$OUT/${NAME}_$K.bvh"; [ -s "$DEST" ] && continue
    HTML=$(curl -sS -m 180 -X POST $SPACE/run/predict -H 'Content-Type: application/json' \
      -d "{\"fn_index\":3,\"data\":[\"$PROMPT\",\"0\",\"IK\"],\"session_hash\":\"lookout\"}" </dev/null)
    HREF=$(echo "$HTML" | grep -oE 'file/[^"\\]+\.bvh' | head -1)
    [ -n "$HREF" ] && curl -sS -m 120 -o "$DEST" "$SPACE/$HREF" </dev/null && echo "ok $NAME $K"
  done
done < "$(dirname "$0")/moves.txt"
