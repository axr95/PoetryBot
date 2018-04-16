import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.io.OutputStreamWriter;
import java.net.HttpURLConnection;
import java.net.MalformedURLException;
import java.net.URL;

import javax.net.ssl.HttpsURLConnection;

// HILFSKLASSE, UM BILDER ZUM SERVER ZU SENDEN
public class PostService {
    private URL serverURL;

    public PostService(String url) {
        try {
            serverURL = new URL(url);
        } catch (MalformedURLException e) {
            e.printStackTrace();
        }
    }
    
    public String PostData(String data) throws IOException, SocketTimeoutException { return PostData(data, 15000); }

    public String PostData(String data, int timeout) throws IOException, SocketTimeoutException {
        HttpURLConnection con = (HttpURLConnection) serverURL.openConnection();
        con.setReadTimeout(timeout);
        con.setConnectTimeout(timeout);
        con.setRequestMethod("POST");
        con.setDoInput(true);
        con.setDoOutput(true);

        OutputStream os = con.getOutputStream();
        BufferedWriter wr = new BufferedWriter(new OutputStreamWriter(os, "UTF-8"));
        wr.write(data);
        wr.flush();
        wr.close();
        os.close();

        int responseCode = con.getResponseCode();
        if (responseCode == HttpsURLConnection.HTTP_OK) {

            BufferedReader in = new BufferedReader(new InputStreamReader(con.getInputStream()));
            StringBuilder sb = new StringBuilder("");
            String line = "";
            while ((line = in.readLine()) != null) {
                sb.append(line);
            }
            in.close();
            return sb.toString();
        }
        return ":ERROR " + responseCode;
    }
}
