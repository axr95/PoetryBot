
// IMPORTS FOR MARKOV CHAIN GENERATOR
import java.util.Arrays;
import java.util.Collection;
import java.util.LinkedList;
import java.util.List;
import java.util.stream.Collectors;

import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Random;
import java.util.concurrent.ConcurrentHashMap;

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
import io.vedder.ml.markov.tokens.file.DelimitToken;
import io.vedder.ml.markov.tokens.file.StringToken;
import io.vedder.ml.markov.LookbackContainer;

class MarkovChainWrapper {
  private MapTokenHolder tokenHolder;
  
  // MARKOV CHAIN PARAMETERS
  private static final int lookback = 2;
  private static final int mapInitialSize = 50000;
  
  private final List<String> punctuation = Arrays.asList(",", ";", ":", ".", "?", "!", "-");

  public MarkovChainWrapper() {
    tokenHolder = new MapTokenHolder(mapInitialSize);
  }
  
  /*  
   *  Creates Markov Chain generator based on another by simply copying the generated token-list
   */  
  private MarkovChainWrapper(MapTokenHolder base) {
    tokenHolder = base;
  }
  
  public void train(String... filePaths) {
    //MARKOV CHAIN
    
    JobManager jm = new JobManager();

    // Fills the TokenHolder with tokens
    for (String filePath : filePaths) {
      FileTokenizer fileTokenizer = new FileTokenizer(tokenHolder, lookback, filePath);
      jm.addTokenizer(fileTokenizer);
    }
    
    jm.runAll();
  }
  
  public String getPoem() {
    return getPoem(null);
  }
 
  public String getPoem(String start) {
    try {
      final Token DELIMIT_TOKEN = DelimitToken.getInstance();
      StringBuilder sb = new StringBuilder();
      sb.append(start);
      LookbackContainer lbc = new LookbackContainer(Integer.MAX_VALUE, DELIMIT_TOKEN);
      if (start != null) {
        lbc.addToken(new StringToken(start));
      }
      
      Token t = null;
      while ((t = tokenHolder.getNext(lbc)) != DELIMIT_TOKEN && t != null) {
        if (!punctuation.contains(t.toString())) {
          sb.append(' ');
        }
        sb.append(t.toString());
        lbc.addToken(t);
      }
      return sb.toString();
    } catch (Exception e) {
      return "No poem for this word :(";
    }
  }
  
}

MarkovChainWrapper loadMarkov(String[] filePaths, String storePath, String md5Path) {
  int startTime = millis();
  println("Loading / creating markov token holder...");
  MarkovChainWrapper result = null;
  byte[] md5computed = getChecksumForFiles(filePaths);
  byte[] md5stored = loadBytes(md5Path);
  boolean canLoadTokenHolder = MessageDigest.isEqual(md5computed, md5stored);
  println((canLoadTokenHolder) ? "Computed md5 checksum is equal to stored md5, loading token holder..." : "md5 checksum is different from stored md5, need to tokenize sources again...");
  if (canLoadTokenHolder) {
    try {
      FileInputStream fis = new FileInputStream(storePath);
      ObjectInputStream ois = new ObjectInputStream(fis);
      result = new MarkovChainWrapper((MapTokenHolder) ois.readObject());
      ois.close();
      fis.close();
    } catch (Exception e) {
      System.err.println("Error when trying to load Token holder: " + e.getMessage());
      System.out.println("Creating new...");
      canLoadTokenHolder = false;
    }
  }
  if (!canLoadTokenHolder) {
    result = new MarkovChainWrapper();
    result.train(filePaths);
    try {
      FileOutputStream fos = new FileOutputStream(storePath);
      ObjectOutputStream oos = new ObjectOutputStream(fos);
      oos.writeObject(result.tokenHolder);
      oos.close();
      fos.close();
      
      saveBytes(md5Path, md5computed);
      
    } catch (IOException e) {
      e.printStackTrace();
      System.err.println("Error when trying to save Token holder: " + e.getMessage()); //<>//
    }
  }
  println("Finished loading / creating token holder after " + (millis() - startTime) + "ms.");
  return result;
}

// https://stackoverflow.com/a/304275
static byte[] getChecksumForFiles(String... filePaths) {
  try {
    MessageDigest md = MessageDigest.getInstance("MD5");
    byte[] buffer = new byte[1024];
    
    for (String sourceFilePath : filePaths) {
      InputStream fis = new FileInputStream(sourceFilePath);
      int numRead;
      do {
        numRead = fis.read(buffer);
        if (numRead > 0) {
          md.update(buffer, 0, numRead);
        }
      } while (numRead != -1);
      fis.close();
    }
    
    return md.digest();
  } catch (Exception e) {
    System.err.println("Error when trying to get Checksum for source files: " + e.getMessage());
  }
  return null;
}
