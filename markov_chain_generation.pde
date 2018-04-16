
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

/*  static is needed in processing for Serialization - since this becomes an inner class,
 *  it has to be a STATIC inner class so it does not depend on the PApplet it is nested
 *  in to be Serializable as well.
 */
static class MarkovChainWrapper {
  private EnhancedTokenHolder tokenHolder;
  
  // MARKOV CHAIN PARAMETERS
  private static final int lookback = 2;
  private static final int mapInitialSize = 50000;
  private static final int numSent = 1;
  
  private final List<String> punctuation = Arrays.asList(",", ";", ":", ".", "?", "!", "-");
  
  
  
  public MarkovChainWrapper() {
    tokenHolder = new EnhancedTokenHolder(mapInitialSize);
  }
  
  public MarkovChainWrapper(String... filePaths) {
    tokenHolder = new EnhancedTokenHolder(mapInitialSize);
    train(filePaths);
  }
  
  /*  Creates Markov Chain generator based on another: the old token-list is copied, and the
   *  filePaths given are additionally tokenized and added to that list.
   */
  public MarkovChainWrapper(MarkovChainWrapper base, String... filePaths) {
    tokenHolder = new EnhancedTokenHolder(base.tokenHolder);
    train(filePaths);
  }
  
  private MarkovChainWrapper(EnhancedTokenHolder base) {
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
  
  private static class EnhancedTokenHolder implements TokenHolder, Serializable {
    private ConcurrentHashMap<LookbackContainer, HashMap<Token, Integer>> tokenMap;
    private Random r = null;
  
    public EnhancedTokenHolder(int mapInitialSize) {
      r = new Random();
      tokenMap = new ConcurrentHashMap<LookbackContainer, HashMap<Token, Integer>>(mapInitialSize);
    }
  
    public EnhancedTokenHolder(EnhancedTokenHolder base) {
      r = new Random();
      tokenMap = new ConcurrentHashMap<LookbackContainer, HashMap<Token, Integer>>(base.tokenMap);
    }
  
    public void addToken(LookbackContainer lbc, Token next) {
      HashMap<Token, Integer> nextElementMap = null;
      if (tokenMap.containsKey(lbc)) {
        nextElementMap = tokenMap.get(lbc);
      } else {
        nextElementMap = new HashMap<Token, Integer>();
      }
  
      if (!nextElementMap.isEmpty() && nextElementMap.containsKey(next)) {
        nextElementMap.put(next, nextElementMap.get(next) + 1);
  
      } else {
        nextElementMap.put(next, 1);
      }
      tokenMap.put(lbc, nextElementMap);
    }
  
    public Token getNext(LookbackContainer look) {
      HashMap<Token, Integer> nextElementList = null;
  
      // Look for the largest lookback container which has a match. May be
      // empty.
      while (!look.isEmpty() && (nextElementList = tokenMap.get(look)) == null) {
        look = look.shrinkContainer();
      }
  
      if (nextElementList == null) {
        throw new RuntimeException("Unable to find match to given input");
      }
  
      int sum = 0;
      // calculate sum
      for (Entry<Token, Integer> entry : nextElementList.entrySet()) {
        sum += entry.getValue();
      }
  
      int randInt = r.nextInt(sum) + 1;
      for (Entry<Token, Integer> entry : nextElementList.entrySet()) {
        if (randInt <= entry.getValue()) {
          return entry.getKey();
        }
        randInt -= entry.getValue();
      }
  
      throw new RuntimeException("Failed to get next token");
    }
  }
}

MarkovChainWrapper loadMarkov(String[] filePaths, String storePath, String md5Path) {
  println("Loading / creating markov token holder...");
  MarkovChainWrapper result = null;
  byte[] md5computed = getChecksumForFiles(filePaths);
  byte[] md5stored = loadBytes(md5Path);
  if (MessageDigest.isEqual(md5computed, md5stored)) {
    println("Computed md5 checksum is equal to stored md5, loading token holder...");
    try {
      FileInputStream fis = new FileInputStream(storePath);
      ObjectInputStream ois = new ObjectInputStream(fis);
      result = new MarkovChainWrapper((MarkovChainWrapper.EnhancedTokenHolder) ois.readObject());
      ois.close();
      fis.close();
    } catch (Exception e) {
      System.err.println("Error when trying to load Token holder: " + e.getMessage());
      exit();
    }
  } else {
    println("md5 checksum is different from stored md5, need to tokenize sources again...");
    result = new MarkovChainWrapper(filePaths);
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
  println("finished loading markov chain generator");
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
