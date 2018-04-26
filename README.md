# PoetryBot
Creates expressive internet poetry out of visual input
------------------------------------------------------
written as Processing sketch with native Java
by axr95 and Fabius42

What it does so far:
----------------------
1) loads a picture from:
    a) a webcam connected to your device or
    b) a webserver (for example, you could send pictures via an android app to the server -> smartphone input)
2) sends the picture to Google Cloud Vision via its API (you need a personal key for that)
3) pulls some labels of the picture content (e.g. "face", "eye", "hair" for a selfie)
4) randomly selects one of the labels
5) and chooses an internet picture similar to the uploaded one
6) uses Google Custom Search API to get 8-10 urls related to the label
7) crawls the urls and reads text between html paragraph brackets
8) saves the crawled text as "labelnamexyz.txt"
9) tokenizes text with markov chain algorithms and creates unique poetry based on it
10) prints the original picture with the generated poem, as well as the most similar image from the web


How to configure it:
-----------------
You can use the following configuration files to specify some settings. Note that you **must specify your API-Keys** in keys.txt before using the program, to be able to connect to the Google APIs.

The variables have to be stored each in its own line, in a "key:value" format. For example, to specify that the output should actually be printed, the data/settings.txt must contain a line with the content "print:true".

KEYS
In the file "keys.txt", you have to specify the following keys:
* **API_KEY_CLOUDVISION**: Google Cloud Vision
* **API_KEY_CUSTOMSEARCH**: Google Custom Search

note: you can easily create an account and get free credits for these services

SETTINGS
in the file "settings.txt" you can set the following (**bold** options are the default values):
* **print** *(true|**false**)*: whether you actually want to print the pictures and the poem (on your standard printer)
* **servermode** *(**enabled**|disabled)*: whether it should be possible to switch to server mode, where the program pulls images from a webserver instead of the camera on the device itself.
* **serverurl-read**: specify url of the server where pictures are stored in base64 (needed for server mode)
* **min-delay**: the minimum delay between requests to the server in server mode (in ms)
* **max-delay**: the maximum delay between requests to the server in server mode (in ms)
* **double-delay-interval**: after so many requests without an image answer, the delay between requests is doubled.

Project dependencies:
--------------------
This Project uses some external libraries. Please refer to https://github.com/processing/processing/wiki/How-to-Install-a-Contributed-Library on how to install those libraries.

The needed libraries are:
* **JChains** - a markov chain generator for java (forked from kyle vedder): https://github.com/axr95/JChains
    * _(there is no .jar ready for download yet, you will have to build it yourself from the source code... I hope I can put it on here sometime soon)_
* **jsoup** - makes javascript-like queries for website content possible: https://jsoup.org/download
* **Video** - a standard processing library for camera input: https://processing.org/reference/libraries/video/index.html
