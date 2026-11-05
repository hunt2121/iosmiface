#!/bin/bash
# Звірка Swift-порту компілятора з еталоном (вихід WatchfaceCompiler.exe у ref/).
# Запускається в CI на одній машині macOS. Результати — у теці swift/.
set -u
W=BandFaceKit/.build/release/wfc
mkdir -p swift/out swift/rebuilt swift/fix swift/fixbin swift/logs
S=swift/logs/summary.tsv
: > $S
for f in ref/faces/*.bin; do
  n=$(basename "$f" .bin)
  $W unpack band10 "$f" "swift/out/$n" --quirks --uidmap "swift/logs/$n.unpack.uidmap" > "swift/logs/$n.unpack.txt" 2>&1; u=$?
  # виправлений режим: розпакування -> збирання (кругова перевірка)
  $W unpack band10 "$f" "swift/fix/$n" > "swift/logs/$n.fix.txt" 2>&1 && \
    $W build band10 "swift/fix/$n" "swift/fixbin/$n.bin" >> "swift/logs/$n.fix.txt" 2>&1; x=$?
  printf "%s\tunpack=%s\tfix=%s\n" "$n" "$u" "$x" >> $S
done
# збирання з маніфестів, які розпакував сам exe (порівнюється з ref/rebuilt)
for d in ref/out/*/; do
  n=$(basename "$d")
  $W build band10 "$d" "swift/rebuilt/$n.bin" --quirks --uidmap "swift/logs/$n.build.uidmap" > "swift/logs/$n.build.txt" 2>&1; b=$?
  printf "%s\tbuild=%s\n" "$n" "$b" >> $S
done
cat $S
