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
import java.util.concurrent.Future;
import java.util.concurrent.Callable;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.security.MessageDigest;

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

//PFADE
String cachePath;
String tempPath;
String fontPath;

//MARKOV CHAIN
private static MarkovChainGenerator markov;
private static String[] filePaths = null;

//SERVER MODE EINSTELLUNGEN
boolean serverMode = false;
boolean serverModePossible = true;
PImage serverImg;
String serverurl_pop;

//MULTITHREADING
ExecutorService threadPool = Executors.newCachedThreadPool();

//BERECHNUNG VIDEO*TEXT
void setup() {
  // ADD WANTED FEATURES HERE
  wantedFeatures = new HashMap<String, Integer>();
  wantedFeatures.put("LABEL_DETECTION", maxResults);
  wantedFeatures.put("WEB_DETECTION", 2);
  //wantedFeatures.put("FACE_DETECTION", 3);
  wantedFeatures.put("IMAGE_PROPERTIES", 1);
  
  cachePath = sketchPath("data") + File.separator + ("cache") + File.separator;
  tempPath = sketchPath("data") + File.separator + ("temp") + File.separator;
  fontPath = sketchPath("data") + File.separator + ("fonts") + File.separator;
  
  String sourceBasePath = sketchPath("data") + File.separator + "poemsource" + File.separator + "prose" + File.separator;
  println(sourceBasePath, cachePath, tempPath, fontPath);
  filePaths = new String[] {
    sourceBasePath + "1984.txt",
    //sourceBasePath + "bible.txt",             // a bit long for debugging, waiting for save mechanism
    sourceBasePath + "book-of-wisdom.txt", 
    //sourceBasePath + "brave-new-world.txt",   // TODO: please sanitize files before adding them here. The other were okayish, but this one is pretty annoying to sanitize to pure UTF-8
    //sourceBasePath + "cryptonomicon.txt",     // also too long
    sourceBasePath + "earthworm-papers.txt",
    sourceBasePath + "neuromancer.txt",
    sourceBasePath + "old-man-and-the-sea.txt"
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
  
  if (serverModePossible && !settings.containsKey("serverurl-read")) {
    println("No serverurl-read specified in settings.txt - Server mode disabled!");
    serverModePossible = false;
    serverMode = false;
  } else {
    serverurl_pop = settings.get("serverurl-read");
  }
  /*
  if (serverMode) {
    Thread serverThread = new Thread() {
      @Override
      public void run() {
        server();
      }
    };
    
    serverThread.run();
  }*/
  
  markov = loadMarkov(filePaths, cachePath + "markov_tokens.gz", 
                                 cachePath + "markov_tokens_md5.bin");
  
  //size(1440, 360);
  size(640, 360);
  String[] cameras = Capture.list();
  video = new Capture(this, cameras[18]);
  video.start();
  font = loadFont(fontPath + "HelveticaNeueLTStd-Bd-48.vlw");
  textFont(font, fontSize);
  background(255);
}

//DARSTELLUNG BASICS
void draw() {
  background(255);
  frameRate (30);
  tint(255, blaesse);


  if (serverMode) {
    if (serverImg != null) {
      image(serverImg, 0, 0, 640, 360);
    } else {
      text("SERVER-MODE", 0, 0, 640, 360);
    }
    
  } else {
    //VIDEO READ
    if (video.available() == true) {
      video.read();
    }
  
    //POSITION VIDEODARSTELLUNG
    image(video, 0, 0, 640, 360);
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
        
        serverThread.run();
      }
    } else if (!serverMode) {
      saveFrame(tempPath + "tmp.jpg");
      // saveFrame("photobooth-###.jpg");
      
      threadPool.execute(new Runnable() { 
        public void run() { 
          processImage(video); 
        } 
      });
    }
  }
}

private void processImage(final PImage image) {
  Future<String> imageStringFuture = threadPool.submit(new Callable<String>() {
    public String call() throws IOException {
      return EncodePImageToBase64(image);
    }
  });
  Future<PImage> imageFuture = CompletableFuture.completedFuture(image);
  processImage(imageStringFuture, imageFuture);
}

// imageString muss ein Base64-codiertes Bild sein
private void processImage(final String imageString) {
  Future<String> imageStringFuture = CompletableFuture.completedFuture(imageString);
  Future<PImage> imageFuture = threadPool.submit(new Callable<PImage>() {
    public PImage call() throws IOException {
      return DecodePImageFromBase64(imageString); 
    }
  });
  processImage(imageStringFuture, imageFuture);
}

// imageString muss ein Base64-codiertes Bild sein, image das dazugehörige Bild (wird nur zum Drucken verwendet)
private void processImage(Future<String> imageStringFuture, Future<PImage> imageFuture) {
  try {
    //ZUGRIFF CLOUD VISION API
    String requestText = getRequestFromImage(imageStringFuture.get());
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
  
            copyStream(imageurl.openStream(), new FileOutputStream(tempPath + "print2.jpg"));
            String mimetype = new MimetypesFileTypeMap().getContentType(tempPath + "print2.jpg");
            success = mimetype.contains("image/jpg");
          } 
          catch (IOException e) {
            System.out.println("Could not download, open next...");
          }
        }
      }
      
      // Mit diesem pg Objekt können wir auf unsere Rechnung zeichnen, ohne auf den Screen zeichnen zu müssen
      // - das ist um einiges sauberer und beugt Problemen vor, da draw() uns so nicht mehr hineinpfuschen kann.
      PGraphics pg = createGraphics(1440, 360);
      pg.beginDraw();
      pg.background(255);
      
      pg.image(imageFuture.get(), 0, 0, 640, 360);
        
      //ZUFALLSAUSWAHL LABEL
      String[] labels = new String[labelCount];
      for (int i=0; i < labelCount; i++) {
        labels[i] = labelObjects.getJSONObject(i).getString("description");
      }        
      
      int index = int(random(labelCount));
      String selectedLabel = labels[index];
      println("selectedLabel: " + selectedLabel);
      
      // ...\cache\webdata\labelname.txt
      String markovFile = cachePath + "webdata" + File.separator + selectedLabel + ".txt";
      
      File f = new File(markovFile);
      
      if (!f.exists()) {
        String[] keywordURLs = getURLsForKeyword(selectedLabel);
        webscrape(keywordURLs, markovFile);
      }
      
      // Momentan wird der Markov Chain Generator jedes Mal neu an den Input angepasst.
      markov = new MarkovChainGenerator();
      markov.train(markovFile);
      
      String poem = markov.getPoem(selectedLabel);
      println(poem);
      
      //DARSTELLUNG DATUM-TEXT
      pg.fill(0);
      
      int x = 20;     // Location of start of text.
      int y = 360;
      
      pg.pushMatrix();
      pg.translate(x,y);
      pg.rotate(3*HALF_PI);
      pg.translate(-x,-y);
      pg.text(date, x, y);
      pg.popMatrix();      
  
      //DARSTELLUNG POEM-TEXT
      pg.fill(0);
      
      int x2 = 660;     // Location of start of text.
      int y2 = 360;
      
      pg.pushMatrix();
      pg.translate(x2,y2);
      pg.rotate(3*HALF_PI);
      pg.translate(-x2,-y2);
      pg.text(poem, x2, y2, 360, 800); //650, 0, 1040, 360
      pg.popMatrix();
      
      //SPEICHERUNG
      pg.save(tempPath + "print.jpg");
  
      //DRUCKEN
      if (settings.getOrDefault("print", "false").equals("true")) {
        Runtime.getRuntime().exec("mspaint /pt " + tempPath + "print.jpg");
        Runtime.getRuntime().exec("mspaint /pt " + tempPath + "print2.jpg");
      }
    }
  } catch (IOException e) {
    System.out.println("error");
  } catch (ExecutionException e) {
    System.err.println("Execution of subtask failed: " + e.getMessage()); 
  } catch (InterruptedException e) {
    System.err.println("Executor of subtasks was interrupted");
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
                    "&cx=003881552290933724291:wdkgsjtvmks" +
                    "&fields=" + URLEncoder.encode("items/link", "UTF-8") + 
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
  println("starting server");
  PostService poster = new PostService(serverurl_pop);
  int tries = 3;
  while (serverMode) {
    try {
      final String imageData = poster.PostData(" ", 10000);
      println("got Picture from Server...");
     
      draw();
      
      threadPool.execute(
        new Runnable() {
          @Override //<>//
          public void run() {
            processImage(imageData);
          }
      });
      
      tries = 3;
      
    } catch (SocketTimeoutException e) {
      // ignore timeout
      System.out.println("timeout occured...");
    } catch (IOException e) {
      System.out.println("ioexception:");
      System.out.println(e.getMessage());
      tries--; //<>//
      if (tries == 0) { serverMode = false; println("connection issue in server mode: falling back to normal mode..."); }
    }
  }
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

public String EncodePImageToBase64(PImage i_Image) throws UnsupportedEncodingException, IOException
{
  String result = null;
  BufferedImage buffImage = (BufferedImage)i_Image.getNative();
  ByteArrayOutputStream out = new ByteArrayOutputStream();
  ImageIO.write(buffImage, "JPG", out);
  byte[] bytes = out.toByteArray();
  result = Base64.getUrlEncoder().encodeToString(bytes);
  
  return result;
}
