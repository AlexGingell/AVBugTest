# AVBugTest

**Description:**
I have an app in production that uses an AVAssetWriter to append multiple images and encode them to produce H264 QuickTime .mov videos.

The same code that has been working correctly from iOS6 to iOS10.3.2 now produces incorrect results under iOS 11 Beta 2 and 3 (15A5318g), but only on hardware (in particular the iPhone 5s), but not in the simulator. 

On at least iPhone 5s, the final video always appears with a green cast, in some cases there is also garbling of the underlying image frames. I have abstracted the code into a single view application for testing purposes. I have verified that this code produces the correct results on iOS 11 simulators (iPad and iPhone), but still produces incorrect results (green cast on video) on my iPhone 5s running iOS 11 Beta 2 & 3.

Can anyone confirm this behaviour?  It certainly seems like a bug in iOS 11 Beta, and my guess is it may be something specific to the hardware encoder on the iPhone 5s.  It would be very useful to see confirmation of this issue and to know if other devices are affected. If not, it would be good to know if I am doing something incorrectly under iOS 11.

**Steps to Reproduce:**
Simply open the attached XCode project and run it on 
a) iOS 11.0 simulator
b) iPhone 5s running iOS 11.0 Beta 3.

Navigate to the photos app and check the video that has been produced.

**Expected Results:** 
Both simulator and device should produce an identical H264 video that adequately resembles the source image sequence. 

**Observed Results:**
The simulator produces the expected result. An iPhone 5s running iOS 11 Beta 3 produces a video with a green cast that does not reflect the source images at all, indicating some kind of encoding error. I have included a video produced on my iPhone 5s under iOS 11.0 Beta 2 for reference - this reflects the incorrect observed result.

**Version:**
iOS 11.0 Beta 2  or Beta 3 (15A5318g), on iPhone 5s.
I expect it may produce incorrect results on other devices too, but I have not been able to verify more than iPhone 5s

**Notes:** 
I wonder whether this is connected to HEIC/HEIF changes in iOS 11.0. I have checked the documentation, but have not been able to find any reason why the attached code should not work on hardware, as opposed to the simulator. I suspect different encoders are being used and there may be an issue with the encoder used on at least the iPhone 5s, if not other devices too. This effectively kills the functionality of many video apps (at least mine!) which still need to support H264 encoded output under iOS11.0 on the affected device(s).

If this is not a bug, but rather a mistake on my part I would dearly like to know what I've done wrong! Thank you for your help. 
