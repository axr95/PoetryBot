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
import java.util.concurrent.atomic.AtomicInteger;
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
HashMap<String, String> poemsource;
HashMap<String, String> translations;

//PFADE
String cachePath;
String baseTempPath;
String fontPath;
String savedPath;

//MARKOV CHAIN
private static MarkovChainGenerator markov;
private static String[] filePaths = null;

//SERVER MODE EINSTELLUNGEN
boolean serverMode = false;
String serverurl_pop;
long minDelay;
long maxDelay;
int doubleDelayInterval;

int candidateCount;
volatile AtomicInteger candidateChoice;

//MULTITHREADING
ExecutorService threadPool = Executors.newCachedThreadPool();
Thread serverThread;
volatile String lastPoem = null;
volatile PImage lastImage = null;


volatile String[] poemCandidates;

String lang;

//BERECHNUNG VIDEO*TEXT
void setup() {
  // ADD WANTED FEATURES HERE
  wantedFeatures = new HashMap<String, Integer>();
  wantedFeatures.put("LABEL_DETECTION", maxResults);
  wantedFeatures.put("WEB_DETECTION", 2);
  //wantedFeatures.put("FACE_DETECTION", 3);
  wantedFeatures.put("IMAGE_PROPERTIES", 1);
  
  cachePath = sketchPath("data") + File.separator + ("cache") + File.separator;
  baseTempPath = sketchPath("data") + File.separator + ("temp") + File.separator;
  fontPath = sketchPath("data") + File.separator + ("fonts") + File.separator;
  savedPath = sketchPath("data") + File.separator + ("saved") + File.separator;
  
  keys = loadConfig("keys.txt");
  settings = loadConfig("settings.txt");
  poemsource = loadConfig("poemsource.txt");
  
  candidateCount = int(settings.getOrDefault("candidate-count", "3"));
  poemCandidates = null;
  
  lang = settings.getOrDefault("language", "en").toLowerCase();
  if (!lang.equals("en")) {
    translations = loadConfig(cachePath + "translations" + File.separator + lang + ".txt");
  }
  
  
  if (poemsource.containsKey("base")) {
    filePaths = poemsource.get("base").split(",");
    String sourceBasePath = sketchPath("data") + File.separator;
    for (int i = 0; i < filePaths.length; i++) {
      filePaths[i] = sourceBasePath + filePaths[i];
    }
    markov = loadMarkov(filePaths, cachePath + "markov_tokens.gz", 
                                   cachePath + "markov_tokens_md5.bin");
  } else {
    markov = new MarkovChainGenerator();
  }
  
  if (boolean(poemsource.get("use-goodpoems"))) {
    markov.train(cachePath + "goodpoems.txt");
  }
                              
  serverMode = false; //("enabled".equals(settings.get("servermode")));
  
  if (serverMode) {
    minDelay = Long.parseLong(settings.getOrDefault("min-delay", "2000"));
    maxDelay = Long.parseLong(settings.getOrDefault("max-delay", "60000"));
    doubleDelayInterval = Integer.parseInt(settings.getOrDefault("double-delay-interval", "10"));
    
    if (!settings.containsKey("serverurl-read")) {
      println("No serverurl-read specified in settings.txt - Server mode disabled!");
      serverMode = false;
    } else {
      serverurl_pop = settings.get("serverurl-read");
    }serverThread = new Thread() {
      @Override
      public void run() {
        server();
      }
    };
    serverThread.start();
  }
  
  //size(1440, 360);
  size(640, 720);
  String[] cameras = Capture.list();
  video = new Capture(this, cameras[18]);
  video.start();
  font = loadFont(fontPath + "TimesModern-Bold-200.vlw");
  textFont(font, fontSize);
  background(255);
}

//DARSTELLUNG BASICS
void draw() {
  background(255);
  frameRate (30);
  tint(255, blaesse);
  if (lastImage == null) {
    //VIDEO READ
    if (video.available() == true) {
      video.read();
    }
    
    //POSITION VIDEODARSTELLUNG
    image(video, 0, 0, 640, 360);
  } else if (poemCandidates != null) {
    image(lastImage, 0, 0, 640, 360);
    final float boxwidth = (float)width / candidateCount - 1f;
    final float boxheight = height - 360f;
    rectMode(CORNERS);
    for (int i = 0; i < candidateCount; i++) {
      fill(0);
      text(poemCandidates[i], (float)(boxwidth * i), 360f, (float)(boxwidth * (i + 1)) - 40f, 360f + boxheight);
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
    if (lastImage == null) {
      saveFrame(baseTempPath + "tmp.jpg");
      // saveFrame("photobooth-###.jpg");
      
      new Thread() {
        public void run() { processImage(video); }
      }.start();
    } else if ('0' <= key && key <= '0' + candidateCount + 1) {
      synchronized(candidateChoice) {
        candidateChoice.set((int)(key - '1'));
        candidateChoice.notify();
      }
    }
  }
}

private void processImage(final PImage image) {
  Future<String> imageStringFuture = threadPool.submit(new Callable<String>() {
    public String call() throws IOException {
      return EncodePImageToBase64(image);
    }
  });
  Future<PImage> imageFuture = CompletableFuture.completedFuture(image.copy());
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
    //EINRICHTUNG TEMPORAERER ORDNER
    File tempFolder = new File(baseTempPath + Thread.currentThread().getId());
    if (tempFolder.exists()) {
      for (File f : tempFolder.listFiles()) {
        if (!f.isDirectory()) {
          f.delete();
        }
      }
    } else {
      tempFolder.mkdirs();
    }
    
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
    
    File internetPictureFile = null;
    JSONArray jsonSimilarImages = jsonResponses.getJSONObject("webDetection").getJSONArray("visuallySimilarImages");
    if (jsonSimilarImages != null && boolean(settings.getOrDefault("usewebimage", "true"))) {
      boolean success = false;
      internetPictureFile = new File(tempFolder, "print2.jpg");
      internetPictureFile.createNewFile();
      for (int i = 0; i < jsonSimilarImages.size() && !success; i++) {
        try {
          String similarImageURL = jsonSimilarImages.getJSONObject(0).getString("url");
          System.out.println(similarImageURL);
          URL imageurl = new URL(similarImageURL);
          
          copyStream(imageurl.openStream(), new FileOutputStream(internetPictureFile));
          String mimetype = new MimetypesFileTypeMap().getContentType(internetPictureFile);
          success = mimetype.contains("image/jpg") || mimetype.contains("image/jpeg");
        } 
        catch (IOException e) {
          System.out.println("Could not download, open next...");
        }
      }
      if (!success) {
        internetPictureFile = null;
      }
    }
    
    
    // Mit diesem pg Objekt können wir auf unsere Rechnung zeichnen, ohne auf den Screen zeichnen zu müssen
    // - das ist um einiges sauberer und beugt Problemen vor, da draw() uns so nicht mehr hineinpfuschen kann.
    PGraphics pg = createGraphics(640, 1800);
    pg.beginDraw();
    pg.background(255);
    pg.textFont(font, fontSize);
    pg.tint(255, blaesse);
    
    
    
    PImage imageToDraw = null;
    if (boolean(settings.getOrDefault("usewebimage", "true")) && internetPictureFile != null) {
      imageToDraw = loadImage(internetPictureFile.getAbsolutePath());
    }
    
    if (imageToDraw == null || imageToDraw.width <= 0 || imageToDraw.height <= 0) {
      imageToDraw = imageFuture.get();
    }
   
    
    
    //ZUFALLSAUSWAHL LABEL
    String[] labels = new String[labelCount];
    for (int i=0; i < labelCount; i++) {
      labels[i] = labelObjects.getJSONObject(i).getString("description");
    }        
    
    int index = int(random(labelCount));
    String selectedLabel = labels[index];
    println("selectedLabel: " + selectedLabel);
    
    if (!"en".equals(lang)) {
      selectedLabel = translateLabel(selectedLabel, lang);
      println("translated to: " + selectedLabel);
    }
    
    MarkovChainGenerator gen;
    gen = new MarkovChainGenerator(markov);
    
    if (boolean(poemsource.getOrDefault("use-webdata", "true"))) {
      // ...\cache\webdata\labelname.txt
      String webMarkovFile = cachePath + "webdata" + File.separator + selectedLabel + ".txt";
      
      File f = new File(webMarkovFile);
      
      if (!f.exists()) {
        String[] keywordURLs = getURLsForKeyword(selectedLabel);
        webscrape(keywordURLs, webMarkovFile);
      }
      
      gen.train(webMarkovFile);
    }
    
    // Momentan wird der Markov Chain Generator von den oben genannten sourcefiles
    // kopiert und um die Webtokens und die goodpoems erweitert.
    
    String poem = getCandidateChoice(gen, imageToDraw, selectedLabel);
    
    if (poem == null) {
      return;
    }
    
    
    pg.fill(0);
    pg.textSize(270);
    pg.text("PoBo", 0, 0, 640, 240);
    
    pg.textSize(48);
    pg.text("Erfahre mehr über PoetryBot!", 0, 240, 640, 310);

    pg.textSize(42);
    pg.text("       // poetrybot.github.io //", 0, 320, 640, 360);
    
    pg.textSize(36);
    pg.text("Unser Bot erschafft expressive Internet-Poesie aus visuellem Input. Das passiert mithilfe von Machine Learning und probabilistischen Verfahren. Wir wollen Menschen aller Altersgruppen, besonders Schüler_innen, das Thema Poesie auf spielerische Weise näherbringen. Bleib informiert, schick uns Feedback an thepoetrybot@gmail.com und sei beim Start dabei!",
            0, 390, 640, 750);

    pg.textSize(36);
    pg.text("Schritt 1: Foto machen und hochladen; Schritt 2: automatisch generiertes Gedicht lesen -> hier ein Beispiel mit einem Foto von uns:", 0, 810, 640, 1000);
            
    pg.textSize(48);
    pg.text("     +++ Dein Bild-Input +++", 0, 990, 640, 1060);
    
    pg.image(imageToDraw, 0, 1050, 640, 360);
    
    pg.textSize(48);
    pg.text("    +++ Generiertes Poem +++", 0, 1440, 640, 60);
    
    pg.fill(0);
    pg.textSize(36);
    pg.text(poem, 0, 1500, 640, 3000);

    pg.endDraw();
    
    PGraphics pgRotated = createGraphics(3000, 640);
    pgRotated.beginDraw();
    pgRotated.background(255);
    pgRotated.pushMatrix();
    pgRotated.rotate(3*HALF_PI);
    pgRotated.translate(-pg.width, 0);
    pgRotated.image(pg, 0, 0);
    pgRotated.popMatrix();
    pgRotated.endDraw();
    
    //SPEICHERUNG
    File printedImageFile = new File(tempFolder, "print.jpg");
    printedImageFile.createNewFile();
    pg.save(printedImageFile.getAbsolutePath());
    
    File saveFolder = new File(savedPath); 
    if (!saveFolder.exists()) {
      saveFolder.mkdir();
    }
    File saveFile = new File(saveFolder, String.format("%s%d%d%d%d%d%d.jpg", selectedLabel.replace(' ', '_'), year(), month(), day(), hour(), minute(), second()));
    while (saveFile.exists()) {
      Thread.sleep(1000);
      saveFile = new File(saveFolder, String.format("%s%d%d%d%d%d%d.jpg", selectedLabel.replace(' ', '_'), year(), month(), day(), hour(), minute(), second()));
    }
    saveFile.createNewFile();
    pgRotated.save(saveFile.getAbsolutePath());
    
    
  
    synchronized (this) {
      //DRUCKEN
      if (settings.getOrDefault("print", "false").equals("true")) {
        Thread.sleep(1000);
        Runtime.getRuntime().exec("mspaint /pt " + saveFile.getAbsolutePath());
      }
      
      lastPoem = poem;
      //println("Is this a good poem? :)");
    }
  } catch (IOException e) {
    System.out.println("error");
  } catch (ExecutionException e) {
    System.err.println("Execution of subtask failed: " + e.getMessage()); 
  } catch (InterruptedException e) {
    System.err.println("Executor of subtasks was interrupted");
  }
}

private String translateLabel(String label, String language) throws UnsupportedEncodingException, IOException {
  synchronized (translations) {
    String cached = translations.get(label);
    if (cached != null) {
      return cached;
    } else {
      PostService poster = new PostService("https://translation.googleapis.com/language/translate/v2/?key=" + keys.get("API_KEY_TRANSLATION") + 
                    "&q=" + URLEncoder.encode(label, "UTF-8") +
                    "&target=" + language +
                    "&source=en" +
                    "&format=text");
                    
      String answer = poster.PostData(" ");
      
      if (answer.startsWith(":ERROR")) {
        return label;
      }
      
      //JSON-KONVERTIERUNG
      JSONObject json = parseJSONObject(URLDecoder.decode(answer, "UTF-8"));
      
      JSONArray online_translations = json.getJSONObject("data").getJSONArray("translations");
      if (online_translations == null || online_translations.size() == 0) {
        return label;
      } else {
        cached = online_translations.getJSONObject(0).getString("translatedText");
        translations.put(label, cached);
        saveConfig(cachePath + "translations" + File.separator + lang + ".txt", translations);
        return cached;
      }
    }
  }
}

private synchronized String getCandidateChoice(MarkovChainGenerator gen, PImage imageToDraw, String selectedLabel) throws InterruptedException {
  candidateChoice = new AtomicInteger();
  poemCandidates = new String[candidateCount];
  int choice;
  do {
    for (int i = 0; i < candidateCount; i++) {
      poemCandidates[i] = gen.getPoem(selectedLabel);
    }
    lastImage = imageToDraw;

    synchronized(candidateChoice) {
      candidateChoice.wait();
      choice = candidateChoice.get();
    }
  } while (choice == candidateCount);
  
  lastImage = null;
  if (choice == -1) {
    return null;
  }
  
  return poemCandidates[choice];
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
                    // EN: "&cx=003881552290933724291:wdkgsjtvmks" +
                    "&cx=" + URLEncoder.encode("003881552290933724291:h5-sku2lxjy", "UTF-8") + 
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
    if (line.startsWith("#") || line.trim().isEmpty())
      continue;
      
    String[] a = line.split(":", 2);
    if (a.length == 2) {
      result.put(a[0], a[1]);
    }
  }
  return result;
}

private void saveConfig(String filename, HashMap<String, String> config) {
  String[] buf = new String[config.size()];
  int i = 0;
  for (java.util.Map.Entry<String, String> kvp : config.entrySet()) {
    buf[i++] = kvp.getKey() + ":" + kvp.getValue();
  }
  saveStrings(filename, buf);
}

void server() {
  println("starting server request thread");
  PostService poster = new PostService(serverurl_pop);
  int tries = 3;
  long currentDelay = minDelay;
  int delayCounter = doubleDelayInterval;
  while (serverMode) {
    try {
      final String imageData = poster.PostData(" ");
      if (imageData.startsWith(":ERROR")) {
        println("server request failure: " + imageData);
        continue;
      } else if (imageData.trim().isEmpty()) {
        delayCounter--;
        if (delayCounter == 0) {
          currentDelay = Math.min(currentDelay * 2, maxDelay);
          delayCounter = doubleDelayInterval;
          println("Doubling the server request interval to " + currentDelay + "ms after " + doubleDelayInterval + " requests without image response");
        }
      } else {
        println("got Picture from Server...");
        
        draw();
        
        threadPool.execute(
          new Runnable() {
            @Override
            public void run() {
              processImage(imageData);
            }
        });
        tries = 3;
      }
      
      Thread.sleep(currentDelay);
    } catch (SocketTimeoutException e) {
      // ignore timeout
      System.out.println("timeout occured...");
    } catch (IOException e) {
      System.out.println("ioexception:");
      System.out.println(e.getMessage());
      tries--;
      if (tries == 0) {
        serverMode = false;
        println("connection issue for server requests: disabling server mode...");
      }
    } catch (InterruptedException e) {
      serverMode = false;
      System.out.println("Server request thread was interrupted. Shutting down...");
    }
  }
  println("servermode was shut down.");
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