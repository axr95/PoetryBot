import processing.video.*;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import javax.activation.MimetypesFileTypeMap;
import static java.lang.Math.*;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;

// DATUM DEFINIEREN

int d = day();    // Values from 1 - 31
int m = month();  // Values from 1 - 12
int y = year();   // 2003, 2004, 2005, etc.
String date = d+"/"+m+"/"+y;

Capture video;

//TEXT-DEFINITIONEN
PFont font;
int fontSize = 24;
int maxResults = 4;

//HELLIGKEIT
int blaesse = 220;

//PIXELPOSITIONEN FÜR DITHERING
int index(int x, int y) {
  return x + y * video.width;
}

//DIVERSE EINSTELLUNGEN
HashMap<String, Integer> wantedFeatures;
HashMap<String, String> keys;
HashMap<String, String> settings;

//MARKOV CHAIN
private static MarkovChainWrapper markov;
private static String[] filePaths = null;

//SERVER MODE EINSTELLUNGEN
boolean serverMode = false;
boolean serverModePossible = true;
String baseurl;
PImage serverImg;



//BERECHNUNG VIDEO*TEXT
void setup() {
  // ADD WANTED FEATURES HERE
  wantedFeatures = new HashMap<String, Integer>();
  wantedFeatures.put("LABEL_DETECTION", maxResults);
  wantedFeatures.put("WEB_DETECTION", 2);
  //wantedFeatures.put("FACE_DETECTION", 3);
  wantedFeatures.put("IMAGE_PROPERTIES", 1);

  filePaths = new String[] {
    sketchPath("poetry\\some imagist poems_clean.txt"), 
    sketchPath("poetry\\african poetry source.txt"), 
    sketchPath("poetry\\1914 poems.txt"), 
    sketchPath("poetry\\drum taps.txt"), 
    sketchPath("poetry\\sword blades and poppy seeds.txt"),
    //sketchPath("poetry\\quran.txt"),
  };
  
  keys = loadConfig("keys.txt");
  settings = loadConfig("settings.txt");
  
  switch (settings.getOrDefault("servermode", "disabled")) {
    case "disabled":
      serverModePossible = false;
      break;
    case "onstart":
      serverModePossible = true;
      serverMode = true;
  }
  
  if (serverModePossible && !settings.containsKey("serverurl")) {
    println("No serverurl specified in settings.txt - Server mode disabled!");
    serverModePossible = false;
    serverMode = false;
  } else {
    baseurl = settings.get("serverurl");
    if (!baseurl.endsWith("/")) {
      baseurl += "/";
    }
  }
  
  markov = new MarkovChainWrapper(filePaths);

  size(1440, 360);
  String[] cameras = Capture.list();
  video = new Capture(this, cameras[18]);
  video.start();
  font = loadFont("HelveticaNeueLTStd-Bd-48.vlw");
  textFont(font, fontSize);
  background(255);
}

//DARSTELLUNG BASICS
void draw() {
  background(255);
  frameRate (30);
  tint(255, blaesse);


  if (!serverMode) {
    //VIDEO READ
    if (video.available() == true) {
      video.read();
    }
  
    //POSITION VIDEODARSTELLUNG
    image(video, 0, 0, 640, 360);
  } else {
    if (serverImg != null) {
      image(serverImg, 0, 0, 640, 360);
    } else {
      text("SERVER-MODE", 0, 0, 640, 360);
    }
  }
  
  //DIVERSE FILTER
  //filter(INVERT);
  //filter(THRESHOLD,0.3);
  //filter(POSTERIZE, 6);
  //filter(BLUR, 15);
}

void exit() {
  super.exit();
  serverMode = false;
}

//INTERAKTION
void keyPressed() {
  if (keyPressed) {
    if (serverModePossible && (key == 's' || key == 'S')) {
      serverMode = !serverMode;
      
      if (serverMode) {
        Thread serverThread = new Thread() {
          @Override
          public void run() {
            server();
          }
        };
        
        serverThread.start();
      }
    } else if (!serverMode) {
    saveFrame("tmp.jpg");
      try {
        File file = new File(sketchPath("tmp.jpg"));
        FileInputStream fis = new FileInputStream(file);
        byte[] imagedata = new byte[(int) file.length()];
        int res = fis.read(imagedata, 0, imagedata.length);
        if (res != imagedata.length) {
          System.err.println("Fehler beim einlesen der datei...");
        }
  
        fis.close();
        
        String imageString = new String(Base64.getEncoder().encode(imagedata), "UTF-8");
        
        processImage(imageString);
      }
      catch (IOException e) {
        e.printStackTrace();
      }
    }
  }
}

// imageString muss ein Base64-codiertes Bild sein
private void processImage(String imageString) {
  try {
    //ZUGRIFF CLOUD VISION API
    String requestText = getRequestFromImage(imageString);
    String answer = accessGoogleCloudVision(requestText);

    //JSON-KONVERTIERUNG
    JSONObject json = parseJSONObject(answer);

    JSONObject jsonResponses = json.getJSONArray("responses").getJSONObject(0);

    JSONArray labelObjects = jsonResponses.getJSONArray("labelAnnotations");

    String infoPrint = "";
    int labelCount = Math.min(maxResults, labelObjects.size());
    for (int i = 0; i < labelCount; i++) {
      String label = labelObjects.getJSONObject(i).getString("description");
      double score = labelObjects.getJSONObject(i).getDouble("score");
      int scorePercent = (int) Math.round(score*100);

      //DEFINITION TEXTAUSGABE
      infoPrint += (label + ": " + scorePercent + "% / ");
    }
    /*fill(0);
    text(infoPrint, 0, height-7/3*fontSize, width, height);
    //System.out.println(label + ": " + score);*/
    System.out.println(infoPrint);

    
    println("Auswertung abgeschlossen.");
    
    
    synchronized (this) {
      
      JSONArray jsonSimilarImages = jsonResponses.getJSONObject("webDetection").getJSONArray("visuallySimilarImages");
      if (jsonSimilarImages != null) {
        boolean success = false;
        for (int i = 0; i < jsonSimilarImages.size() && !success; i++) {
          try {
            String similarImageURL = jsonSimilarImages.getJSONObject(0).getString("url");
            System.out.println(similarImageURL);
            URL imageurl = new URL(similarImageURL);
  
            copyStream(imageurl.openStream(), new FileOutputStream(sketchPath("print2.jpg")));
            String mimetype = new MimetypesFileTypeMap().getContentType(sketchPath("print2.jpg"));
            success = mimetype.contains("image/jpg");
          } 
          catch (IOException e) {
            System.out.println("Could not download, open next...");
          }
        }
      }
      

      //SPEICHERUNG
      saveFrame("photobooth-###.jpg");
      saveFrame("print.jpg");
  
  
  
      //ZUFALLSAUSWAHL LABEL
      String[] labels = new String[labelCount];
      for (int i=0; i < labelCount; i++) {
        labels[i] = labelObjects.getJSONObject(i).getString("description");
      }        
      
      int index = int(random(labelCount));
      String selectedLabel = labels[index];
      println("selectedLabel: " + selectedLabel);
      
      String markovFile = sketchPath("webdata\\" + selectedLabel + ".txt");
      File f = new File(markovFile);
      
      if (!f.exists()) {
        String[] keywordURLs = getURLsForKeyword(selectedLabel);
        webscrape(keywordURLs, markovFile);
      }
      
      markov.train(markovFile);
      
      String poem = markov.getPoem(selectedLabel);
      println(poem);
  
      //DARSTELLUNG DATUM-TEXT
      fill(0);
      
      int x = 20;     // Location of start of text.
      int y = 360;
      
      pushMatrix();
      translate(x,y);
      rotate(3*HALF_PI);
      translate(-x,-y);
      text(date, x, y);
      popMatrix();      
  
      //DARSTELLUNG POEM-TEXT
      fill(0);
      
      int x2 = 660;     // Location of start of text.
      int y2 = 360;
      
      pushMatrix();
      translate(x2,y2);
      rotate(3*HALF_PI);
      translate(-x2,-y2);
      text(poem, x2, y2, 360, 800); //650, 0, 1040, 360
      popMatrix();
      
      saveFrame("print.jpg");
  
      //DRUCKEN
      if (settings.getOrDefault("print", "false").equals("true")) {
        Runtime.getRuntime().exec("mspaint /pt " + sketchPath("print.jpg"));
        Runtime.getRuntime().exec("mspaint /pt " + sketchPath("print2.jpg"));
      }
    }
  } catch (IOException e) {
    System.out.println("error");
  }
}



// helper to save image from web

public static void copyStream(InputStream is, OutputStream os) throws IOException {
  byte[] b = new byte[2048];
  int length;
  while ((length = is.read(b)) != -1) {
    os.write(b, 0, length);
  }


  is.close();
  os.flush();
  os.close();
}

// imageString muss ein Base64-codiertes Bild sein
private String getRequestFromImage(String imageString) {
  StringBuilder sb = new StringBuilder();
  sb.append("{\"requests\":[{\"image\":{\"content\":\"");
  sb.append(imageString);
  sb.append("\"},\"features\":[");
  // adding features as stored in wantedFeatures
  for (String featureName : wantedFeatures.keySet()) {
    sb.append("{\"type\":\"");
    sb.append(featureName);
    sb.append("\",\"maxResults\":");
    sb.append(wantedFeatures.get(featureName));
    sb.append("},");
  }
  sb.append("]}]}");
  return sb.toString();
}

private String accessGoogleCloudVision(String requestText) throws MalformedURLException, IOException {
  byte[] requestData = requestText.getBytes(StandardCharsets.UTF_8);
  URL url = new URL("https://vision.googleapis.com/v1/images:annotate?key=" + keys.get("API_KEY_CLOUDVISION"));
  HttpURLConnection con = (HttpURLConnection)url.openConnection();
  con.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
  con.setDoOutput(true);
  con.setDoInput(true);
  con.setRequestMethod("POST");
  con.setFixedLengthStreamingMode(requestData.length);
  con.connect();

  OutputStream os = con.getOutputStream();
  os.write(requestData);
  os.flush();

  System.out.println(con.getResponseCode());
  InputStream is = con.getInputStream();
  BufferedReader reader = new BufferedReader(new InputStreamReader(is));

  String answer;
  StringBuilder sb = new StringBuilder();
  while ((answer = reader.readLine()) != null) {
    sb.append(answer);
  }
  con.disconnect();
  return sb.toString();
}


public String[] getURLsForKeyword(String keyword) throws IOException {
  URL url = new URL("https://www.googleapis.com/customsearch/v1?key=" + keys.get("API_KEY_CUSTOMSEARCH") + 
                    "&cx=003881552290933724291:wdkgsjtvmks&fields=" + URLEncoder.encode("items/link", "UTF-8") + 
                    "&q=" + URLEncoder.encode(keyword, "UTF-8"));
  HttpURLConnection con = (HttpURLConnection)url.openConnection();
  BufferedReader reader = new BufferedReader(new InputStreamReader(con.getInputStream()));
  
  StringBuilder sb = new StringBuilder();
  String answer;
  while ((answer = reader.readLine()) != null) {
    sb.append(answer);
  }
  answer = sb.toString();
  
  //JSON-KONVERTIERUNG
  JSONObject json = parseJSONObject(answer);
  
  String[] res;
  JSONArray items = json.getJSONArray("items");
  if (items == null) {
    return null;
  } else {
    res = new String[items.size()];
  }
  
  for (int i = 0; i < items.size(); i++) {
    res[i] = items.getJSONObject(i).getString("link");
  }
  
  return res;
  
}

private HashMap<String, String> loadConfig(String filename) {
  String[] keylines = loadStrings(filename);
  HashMap<String, String> result = new HashMap<String, String>();
  for (String line : keylines) {
    String[] a = line.split(":", 2);
    if (a.length == 2) {
      result.put(a[0], a[1]);
    }
  }
  return result;
}

void server() {
  ExecutorService imageExecutioner = Executors.newFixedThreadPool(4);
  PostService poster = new PostService(baseurl + "pop.php");
  while (serverMode) {
    try {
      final String imageData = poster.PostData("", 60000);
      
      serverImg = DecodePImageFromBase64(imageData);
      
      processImage(imageData);
      
      /*
      imageExecutioner.execute(
        new Runnable() {
          @Override
          public void run() {
            processImage(imageData);
        }
      });*/
      
    } catch (SocketTimeoutException e) {
      // ignore timeout
    } catch (IOException e) {
      println("connection issue in server mode: falling back to normal mode...");
      serverMode = false;
    }
  }
  imageExecutioner.shutdown();
  
}

// from https://forum.processing.org/two/discussion/6958/pimage-base64-encode-and-decode
public PImage DecodePImageFromBase64(String i_Image64) throws IOException
{
   PImage result = null;
   byte[] decodedBytes = Base64.getUrlDecoder().decode(i_Image64);
 
   ByteArrayInputStream in = new ByteArrayInputStream(decodedBytes);
   BufferedImage bImageFromConvert = ImageIO.read(in);
   BufferedImage convertedImg = new BufferedImage(bImageFromConvert.getWidth(), bImageFromConvert.getHeight(), BufferedImage.TYPE_INT_ARGB);
   convertedImg.getGraphics().drawImage(bImageFromConvert, 0, 0, null);
   result = new PImage(convertedImg);
   
   return result;
}
