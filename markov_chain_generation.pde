
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
  private EnhancedTokenHolder tokenHolder;
  
  // MARKOV CHAIN PARAMETERS
  private static final int lookback = 2;
  private static final int mapInitialSize = 50000;
  private static final int numSent = 1;
  
  private List<String> punctuation = Arrays.asList(",", ";", ":", ".", "?", "!", "-");

  
  public MarkovChainWrapper() {
    tokenHolder = new EnhancedTokenHolder(mapInitialSize);
  }
  
  public MarkovChainWrapper(String... filePaths) {
    tokenHolder = new EnhancedTokenHolder(mapInitialSize);
    train(filePaths);
  }
  
  public MarkovChainWrapper(MarkovChainWrapper template, String... filePaths) {
    tokenHolder = new EnhancedTokenHolder(template.tokenHolder);
    train(filePaths);
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
  
  class EnhancedTokenHolder implements TokenHolder {
    private Map<LookbackContainer, Map<Token, Integer>> tokenMap;
    private Random r = null;
  
    public EnhancedTokenHolder(int mapInitialSize) {
      r = new Random();
      tokenMap = new ConcurrentHashMap<>(mapInitialSize);
    }
  
    public EnhancedTokenHolder(EnhancedTokenHolder base) {
      r = new Random();
      tokenMap = new ConcurrentHashMap<>(base.tokenMap);
    }
  
    public void addToken(LookbackContainer lbc, Token next) {
      Map<Token, Integer> nextElementMap = null;
      if (tokenMap.containsKey(lbc)) {
        nextElementMap = tokenMap.get(lbc);
      } else {
        nextElementMap = new HashMap<>();
      }
  
      if (!nextElementMap.isEmpty() && nextElementMap.containsKey(next)) {
        nextElementMap.put(next, nextElementMap.get(next) + 1);
  
      } else {
        nextElementMap.put(next, 1);
      }
      tokenMap.put(lbc, nextElementMap);
    }
  
    public Token getNext(LookbackContainer look) {
      Map<Token, Integer> nextElementList = null;
  
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
