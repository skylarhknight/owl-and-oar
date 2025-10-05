# Owl & Oar

A fishing sim for Playdate. Press A to cast your line, wait for the owl to hoot, then press A again to hook your catch! Use the reel to reel in your fish. Avoid reeling in too fast or you might lose your catch!

## Overview
* **Core loop**: Cast → Wait → Hook → Reel → Catch/Snap → Repeat
* Crank-first gameplay: Charge cast power and reel with the crank.
* **Feedback**:
  * **Owl cue**: Owl switches to an alert pose briefly when there’s a bite.
  * **Tension meter**: Fill bar shows line stress (snap at max).
  * **Reel-In bar**: Progress toward landing the fish.
  * **Cards**: Catch card (“YOU CAUGHT A …”) or Snap card (“LINE SNAPPED!”).
* **Fish variety**: Common to rare fish with personality-filled descriptions. Fish also vary in difficulty to catch, with certain attributes (ex. strength, rarity, movement patterns) affecting how challenging they are to reel in.

<img width="1800" height="1200" alt="fishes" src="https://github.com/user-attachments/assets/c1e1727d-f81c-4523-a385-8a9c1ffe08ed" />


## Controls
**A Button**
* Idle → Start Casting (begin charging power with the crank).
* Casting → Release cast (go to Waiting).
* On instruction pages or popups (Caught/Snapped) → Close card (back to Idle).

**B Button**
* Waiting → Opens bucket menu.
* Hooking (bite window) → Hook the fish (go to Reeling).

**Crank**
* Casting → Turn to build cast power (either direction).
* Reeling →
  * Forward (positive): Reels fish in, but increases tension.
  * Backward (negative): Lets out slack, reducing tension (but gives distance back).

**Visual Cues**
* **Owl**: Flashes to alert for ~1s when a fish bites (press B!).
* **Tension Meter**: Visible only while Reeling.

* **Reel-In Bar**: Shows progress toward landing the fish.

