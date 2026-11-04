# Key sounds (SPEC 5.3)

`KeyboardExtension/Resources/key_press_{click,delete,modifier}.caf` are Apple's own key sounds from the iOS 27.1 simulator runtime, peak-normalized from about -8.5 dBFS to -1 dBFS (+7.5 to +7.7 dB). To redo them, from a scratch folder:

```zsh
D="/Library/Developer/CoreSimulator/Volumes/iOS_24A94232/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.1.simruntime/Contents/Resources/RuntimeRoot/System/Library/Audio/UISounds"
R=<repo>/KeyboardExtension/Resources
for f in key_press_click key_press_delete key_press_modifier; do
  afconvert -f WAVE -d LEI16 "$D/$f.caf" $f.wav
  python3 -I <repo>/docs/reference/harness/normalize.py $f.wav $f-loud.wav
  afconvert -f caff -d LEI16 $f-loud.wav $R/$f.caf
done
```
