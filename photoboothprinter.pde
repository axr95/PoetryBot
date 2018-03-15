import processing.video.*;

import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.Map;
import javax.activation.MimetypesFileTypeMap;
import static java.lang.Math.*;


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

//MARKOV CHAIN
private static MarkovChainWrapper markov;
private static String[] filePaths = null;


//BERECHNUNG VIDEO*TEXT
void setup() {
  // ADD WANTED FEATURES HERE
  wantedFeatures = new HashMap<String, Integer>();
  wantedFeatures.put("LABEL_DETECTION", maxResults);
  wantedFeatures.put("WEB_DETECTION", 2);
  //wantedFeatures.put("FACE_DETECTION", 3);
  wantedFeatures.put("IMAGE_PROPERTIES", 1);
  
  filePaths = new String[] {sketchPath("poetry\\some imagist poems_clean.txt"),
                                          sketchPath("poetry\\african poetry source.txt"),
                                          sketchPath("poetry\\1914 poems.txt"),
                                          sketchPath("poetry\\drum taps.txt"),
                                          sketchPath("poetry\\sword blades and poppy seeds.txt")
                                        };
                                         
  
  markov = new MarkovChainWrapper(filePaths);
  
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
      
      String firstLabel = null;
      if (labelObjects.size() > 0) {
         firstLabel = labelObjects.getJSONObject(0).getString("description");
      }

      String poem = markov.getPoem(firstLabel);
      
      println("firstLabel: " + firstLabel);
      println(poem);

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
