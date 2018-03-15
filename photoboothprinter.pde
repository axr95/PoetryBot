import processing.video.*;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import javax.activation.MimetypesFileTypeMap;
import static java.lang.Math.*;

// IMPORTS FOR MARKOV CHAIN GENERATOR
import java.util.Arrays;
import java.util.Collection;
import java.util.LinkedList;
import java.util.List;
import java.util.stream.Collectors;

import org.apache.log4j.Level;
import org.apache.log4j.Logger;

import io.vedder.ml.markov.consumer.TokenConsumer;
import io.vedder.ml.markov.consumer.file.FileTokenConsumer;
import io.vedder.ml.markov.generator.Generator;
import io.vedder.ml.markov.generator.file.FileGenerator;
import io.vedder.ml.markov.holder.MapTokenHolder;
import io.vedder.ml.markov.holder.TokenHolder;
import io.vedder.ml.markov.threading.JobManager;
import io.vedder.ml.markov.tokenizer.file.FileTokenizer;
import io.vedder.ml.markov.tokens.Token;

Capture video;

//TEXT-DEFINITIONEN
PFont font;
int fontSize = 32;
int maxResults = 4;

//HELLIGKEIT
int blaesse = 220;

//PIXELPOSITIONEN FÜR DITHERING
int index(int x, int y) {
  return x + y * video.width;
}

HashMap<String, Integer> wantedFeatures;

// MARKOV CHAIN PARAMETERS
private static int lookback = 2;
private static int mapInitialSize = 50000;
private static int numSent = 1;
private static List<String> filePaths = null;
TokenHolder tokenHolder;

//BERECHNUNG VIDEO*TEXT
void setup() {
  // ADD WANTED FEATURES HERE
  wantedFeatures = new HashMap<String, Integer>();
  wantedFeatures.put("LABEL_DETECTION", maxResults);
  wantedFeatures.put("WEB_DETECTION", 2);
  //wantedFeatures.put("FACE_DETECTION", 3);
  wantedFeatures.put("IMAGE_PROPERTIES", 1);
  
  filePaths = Arrays.asList(new String[] {sketchPath("some imagist poems_clean.txt")});
  
  //MARKOV CHAIN
    tokenHolder = new MapTokenHolder(mapInitialSize);
    
    JobManager jm = new JobManager();

    // Fills the TokenHolder with tokens
    for (String filePath : filePaths) {
      FileTokenizer fileTokenizer = new FileTokenizer(tokenHolder, lookback, filePath);
      jm.addTokenizer(fileTokenizer);
    }
    
    jm.runAll();
  
  size(640, 430);
  String[] cameras = Capture.list();
  video = new Capture(this, cameras[18]);
  video.start();
  font = loadFont("HelveticaNeueLTStd-BdCnO-48.vlw");
  textFont(font, fontSize);
  background(255);
}    

//DARSTELLUNG BASICS
void draw() {
  background(255);
  frameRate (30);
  tint(255, blaesse);

  //DARSTELLUNG DITHERING
  /* video.loadPixels();
   for (int y = 0; y < video.height-1; y++) {
   for (int x = 1; x < video.width-1; x++) {
   color pix = video.pixels[index(x, y)];
   float oldR = red(pix);
   float oldG = green(pix);
   float oldB = blue(pix);
   int factor = 1;
   int newR = round(factor * oldR / 255) * (255/factor);
   int newG = round(factor * oldG / 255) * (255/factor);
   int newB = round(factor * oldB / 255) * (255/factor);
   video.pixels[index(x, y)] = color(newR, newG, newB);
   
   float errR = oldR - newR;
   float errG = oldG - newG;
   float errB = oldB - newB;
   
   int index = index(x+1, y  );
   color c = video.pixels[index];
   float r = red(c);
   float g = green(c);
   float b = blue(c);
   r = r + errR * 7/16.0;
   g = g + errG * 7/16.0;
   b = b + errB * 7/16.0;
   video.pixels[index] = color(r, g, b);
   
   index = index(x-1, y+1  );
   c = video.pixels[index];
   r = red(c);
   g = green(c);
   b = blue(c);
   r = r + errR * 3/16.0;
   g = g + errG * 3/16.0;
   b = b + errB * 3/16.0;
   video.pixels[index] = color(r, g, b);
   
   index = index(x, y+1);
   c = video.pixels[index];
   r = red(c);
   g = green(c);
   b = blue(c);
   r = r + errR * 5/16.0;
   g = g + errG * 5/16.0;
   b = b + errB * 5/16.0;
   video.pixels[index] = color(r, g, b);
   
   index = index(x+1, y+1);
   c = video.pixels[index];
   r = red(c);
   g = green(c);
   b = blue(c);
   r = r + errR * 1/16.0;
   g = g + errG * 1/16.0;
   b = b + errB * 1/16.0;
   video.pixels[index] = color(r, g, b);
   }
   }
   video.updatePixels(); */

  //VIDEO READ
  if (video.available() == true) {
    video.read();
  }

  //POSITION VIDEODARSTELLUNG
  image(video, 0, 0, 640, 360);

  //DIVERSE FILTER
  //filter(INVERT);
  //filter(THRESHOLD,0.3);
  //filter(POSTERIZE, 6);
  //filter(BLUR, 15);
}

//INTERAKTION
void mousePressed() {
  if (mousePressed) {
    saveFrame("tmp.jpg");


    //ZUGRIFF CLOUD VISION API
    try {
      URL url;

      File file = new File(sketchPath("tmp.jpg"));
      FileInputStream fis = new FileInputStream(file);
      byte[] imagedata = new byte[(int) file.length()];
      int res = fis.read(imagedata, 0, imagedata.length);
      if (res != imagedata.length) {
        System.err.println("Fehler beim einlesen der datei...");
      }

      fis.close();
      String imageString = new String(Base64.getEncoder().encode(imagedata), "UTF-8");

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
      String requestText = sb.toString();

      //requestText = "asdfasdf";
      byte[] requestData = requestText.getBytes(StandardCharsets.UTF_8);
      url = new URL("https://vision.googleapis.com/v1/images:annotate?key=AIzaSyBPpGfELFb4hPG67av_MuZP-EeIqSZNvZY");
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
      sb = new StringBuilder();
      while ((answer = reader.readLine()) != null) {
        sb.append(answer);
      }
      answer = sb.toString();
      // System.out.println(answer);

      //JSON-KONVERTIERUNG
      JSONObject json = parseJSONObject(answer);
      
      JSONObject jsonResponses = json.getJSONArray("responses").getJSONObject(0);
      JSONArray jsonSimilarImages = jsonResponses.getJSONObject("webDetection").getJSONArray("visuallySimilarImages");
      if (jsonSimilarImages != null) {
          boolean success = false;
          for (int i = 0; i < jsonSimilarImages.size() && !success; i++) {
            try {
              String similarImageURL = jsonSimilarImages.getJSONObject(0).getString("url");
              System.out.println(similarImageURL);
              URL imageurl = new URL(similarImageURL);
              
              copyStream(imageurl.openStream(), new FileOutputStream(sketchPath("print.jpg")));
              String mimetype = new MimetypesFileTypeMap().getContentType(sketchPath("print.jpg"));
              success = mimetype.contains("image/jpeg");
              
            } catch (IOException e) {
              System.out.println("Could not download, open next...");
            }
          }
          
          
      }
      
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
      fill(0);
      text(infoPrint, 0, height-7/3*fontSize, width, height);
      //System.out.println(label + ": " + score);
      System.out.println(infoPrint);

      con.disconnect();
      println("Auswertung abgeschlossen.");

      //SPEICHERUNG
      saveFrame("photobooth-###.jpg");
      //saveFrame("print.jpg");
      
      

    // Uses the TokenHolder to generate Collections of tokens.
    Generator g = new FileGenerator(tokenHolder, lookback);

    // Takes Collections of tokens and consumes them
    TokenConsumer tc = new FileTokenConsumer();

    // Kicks off the tokenization process

    Collection<Token>[] tokensCollections = new Collection[numSent];

    // Creates Lists of tokens
    for (int i = 0; i < numSent; i++) {
      tokensCollections[i] = (g.generateTokenList());
    }

    // Creates lazy collections of tokens
    //for (int i = 0; i < (numSent / 2 + numSent % 2); i++) {
    //  tokensCollections.add(g.generateLazyTokenList());
    //}

    // Consumer consumes both types of collections
    for (Collection<Token> tlist : tokensCollections) {
      tc.consume(tlist);
    }
    
      

      //DRUCKEN
      /*try {
        Runtime.getRuntime().exec("mspaint /pt " + sketchPath("print.jpg"));
      } 
      catch (IOException e) {
        println("error");
      }*/
    } 
    catch (Exception e) {
      e.printStackTrace();
    }
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