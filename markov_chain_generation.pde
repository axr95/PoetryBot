
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
import io.vedder.ml.markov.tokens.file.DelimitToken;
import io.vedder.ml.markov.tokens.file.StringToken;
import io.vedder.ml.markov.LookbackContainer;

class MarkovChainWrapper {  
  private TokenHolder tokenHolder;
  
  // MARKOV CHAIN PARAMETERS
  private static final int lookback = 2;
  private static final int mapInitialSize = 50000;
  private static final int numSent = 1;
  
  public MarkovChainWrapper() {
    tokenHolder = new MapTokenHolder(mapInitialSize);
  }
  
  public MarkovChainWrapper(String... filePaths) {
    train(filePaths);
  }
  
  public void train(String... filePaths) {
    //MARKOV CHAIN
    tokenHolder = new MapTokenHolder(mapInitialSize);
    
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
    
    final Token DELIMIT_TOKEN = DelimitToken.getInstance();
    StringBuilder sb = new StringBuilder();
    sb.append(start);
    
    LookbackContainer lbc = new LookbackContainer(Integer.MAX_VALUE, new StringToken(start));
    Token t = null;
    while ((t = tokenHolder.getNext(lbc)) != DELIMIT_TOKEN && t != null) {
      sb.append(' ');
      sb.append(t.toString());
      lbc.addToken(t);
    }
    sb.append(DELIMIT_TOKEN);
    return sb.toString();
  }
  
  
  
  
}
