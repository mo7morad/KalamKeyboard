# Key sounds (SPEC 5.3)

`KeyboardExtension/Resources/key_press_{click,delete,modifier}.wav` are Apple's own key sounds from the iOS 27.1 simulator runtime, unchanged (peak about -8.5 dBFS), converted to 16-bit WAV so the keyboard can scale them for the "Louder" setting. To redo them:

```zsh
D="/Library/Developer/CoreSimulator/Volumes/iOS_24A94232/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 27.1.simruntime/Contents/Resources/RuntimeRoot/System/Library/Audio/UISounds"
for f in key_press_click key_press_delete key_press_modifier; do
  afconvert -f WAVE -d LEI16 "$D/$f.caf" <repo>/KeyboardExtension/Resources/$f.wav
done
```
