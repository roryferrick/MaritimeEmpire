MARITIME EMPIRE ON A MAC - READ ME FIRST
=======================================

This test build isn't signed with an Apple developer account, so macOS
blocks it the first time and may say it "is damaged and can't be opened".
It isn't damaged. Do this once:

1. Drag "Maritime Empire.app" into your Applications folder.

2. Open Terminal (press Cmd+Space, type Terminal, press Return).

3. Copy this whole line, paste it into Terminal and press Return:

   xattr -cr "/Applications/Maritime Empire.app"

   (Nothing is printed when it works.)

4. Open Maritime Empire from Applications as usual.

If it still won't open, paste this line into Terminal and send the text
that appears to whoever sent you the game:

   "/Applications/Maritime Empire.app/Contents/MacOS/Maritime Empire"
