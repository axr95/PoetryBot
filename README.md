# PoetryBot
Creates expressive internet poetry out of visual input
------------------------------------------------------
written as Processing sketch with native Java
by axr95 and Fabius42

-> What it does so far:
----------------------
1) loads a picture from:
    a) a webcam connected to your device or
    b) a homeserver (you can send pictures via an android app to the server -> smartphone input)
2) sends pictures to Google Cloud Vision via its API (you need a personal key for that)
3) pulls some labels of the picture content (e.g. "face", "eye", "hair" for a selfie)
4) randomly selects one of the labels
5) and chooses an internet picture similar to the uploaded one
6) uses Google Custom Search API to get 8-10 urls related to the label
7) crawls the urls and reads text between <p></p>
8) saves the crawled text as "labelnamexyz.txt"
9) tokenizes text with markov chain algorithms and creates unique poetry based on it


-> How to use it:
-----------------
SETTINGS
in the file "settings.txt" you can set the following:
  1) printing (you print what you load)
  2) servermode (do not print from device, but from server)
  3) specify url of server where pictures are stored in base64
KEYS
to actually use the program you need keys for:
  1) Google Cloud Vision
  2) Google Custom Search
  note: you can easily create an account and get free credits for these services
  
  
