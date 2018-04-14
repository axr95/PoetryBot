//webscraper//

import org.jsoup.helper.*;
import org.jsoup.*;
import org.jsoup.nodes.*;
import org.jsoup.parser.*;
import org.jsoup.select.*;
import org.jsoup.internal.*;
import org.jsoup.safety.*;

void webscrape(String url) {
  //random number for file title is chosen (goodie)
  float f = random(999);
  int r = int(f);
  
  //filetitle is defined
  String filetitle = "webtext-#" + r + ".txt";
 
  webscrape(url, filetitle);
}

void webscrape(String url, String destination) {
  webscrape(new String[] { url }, destination);
}

void webscrape(String[] urls, String destination) {
  ArrayList<String> lines = new ArrayList<String>();
  for (String url : urls) {
    try {
        Document doc = Jsoup.connect(url).get();
        
        // from https://stackoverflow.com/questions/17161243/how-to-extract-text-of-paragraph-from-html-using-jsoup?rq=1
        Elements paragraphs = doc.select("p");
        
        for (Element p : paragraphs) {
          lines.add(p.text().replace("\\[.*?\\]", "")); 
        }
    } catch (Exception e) {
        e.printStackTrace();  
    }
  }
  String[] linesArray = new String[lines.size()];
  lines.toArray(linesArray);
  saveStrings(destination, linesArray);
}
