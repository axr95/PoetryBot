from flask import Flask, render_template, request, Response
from werkzeug import urls
import argparse
import os
import sys

import json
import gzip
import pandas

sys.path.insert(0, "..")
import vlq, tokentools, poem_metrics


BASEPATH = './data'

app = Flask(__name__)

@app.before_first_request
def init():
    if not os.path.exists(BASEPATH):
        os.mkdir(BASEPATH)
    if not os.path.isfile(os.path.join(BASEPATH, "favourites.txt")):
        open(os.path.join(BASEPATH, "favourites.txt"), "a").close()
    
@app.context_processor
def provideRunids():
    return {"runids": [name for name in os.listdir(BASEPATH) if os.path.isdir(os.path.join(BASEPATH, name))],
            "url_fix": urls.url_fix}


@app.route('/')
def getMain():
    favourites = []
    with open(os.path.join(BASEPATH, "favourites.txt")) as fo:
        for line in fo:
            (runid, ep, poem) = line.strip().split(":")
            jsonpoem = json.loads(getPoem(runid, int(ep), int(poem)))
            favourites.insert(0, (jsonpoem["poem"], line))
    return render_template("home.html", favouritedPoems=favourites)

@app.route('/runs/<string:runid>')
def getRun(runid):
    with open(os.path.join(BASEPATH, runid, "args.json"), "r", encoding="utf8") as fo:
        runArgs = json.load(fo)
    del runArgs["output"]

    return render_template("runview.html", epochMax=runArgs["epochs"]-1, poemMax=runArgs["predict_count"]-1, runArgs=runArgs)


@app.route('/data/<string:runid>/<int:epoch>')
def getEpochStats(runid, epoch):
    with open(os.path.join(BASEPATH, runid, "stats.csv"), "r", encoding="utf8") as fo:
        # simple csv-row to json with pandas not easily possible (for single rows) because of this bug:
        # https://github.com/pandas-dev/pandas/issues/11617
        columnnames = next(fo).strip().split(",")
        for line in fo:
            if line.startswith("%d," % epoch):
                kvp = zip(columnnames, line.rstrip().split(","))
                jsonstring = "{" + ",".join(['"'+k+'":'+v for k,v in kvp if not k.startswith("__")]) + "}"
                # print(jsonstring)
                return jsonstring

    
@app.route('/data/<string:runid>/<int:epoch>/<int:poemid>')
def getPoem(runid, epoch, poemid=0):
    with open(os.path.join(BASEPATH, runid, "args.json"), "r", encoding="utf8") as fo:
        runArgs = json.load(fo)
    
    poemlen = runArgs["predict_len"] + runArgs["word_lookback"]
    start = poemid * poemlen
    end = start + poemlen
    
    stats = pandas.read_csv(os.path.join(BASEPATH, runid, "stats.csv"))
    offset = stats.at[epoch, "__vlqpos"]
    del stats
    
    with gzip.open(os.path.join(BASEPATH, runid, "poems_encoded.vlq.gz"), "rb") as fo:
        poemWords = vlq.loadrange(fo, start, end, offset)
    
    (dictIndex, _) = tokentools.loadDictFromFile(os.path.join(BASEPATH, runid, "vocabulary.txt"))
    
    poem = tokentools.renderText(poemWords, dictIndex, startlen=runArgs["word_lookback"])
    
    obj = {"poem": "<br/>".join(poem.strip().split("\n")), "favourite": False}

    with open(os.path.join(BASEPATH, "favourites.txt"), "r") as fo:
        for line in fo:
            if line == '{}:{}:{}\n'.format(runid, epoch, poemid):
                obj["favourite"] = True
                break
    
    return json.dumps(obj)


@app.route('/favourite', methods=['POST'])
def postFavourite():
    favrequest = request.form
    favstring = favrequest.get('favstring')
    if favstring is None:
        favstring = ':'.join(map(lambda x: favrequest.get(x), ['runid', 'epoch', 'poemid'])) + '\n'

    unfav = favrequest.get('unfavourite', False)
    # TODO: implement unfavourite
    with open(os.path.join(BASEPATH, "favourites.txt"), "r+") as fo:
        if unfav:
            lines = fo.readlines()
            fo.seek(0)
            for line in lines:
                if not favstring == line:
                    fo.write(line)
            fo.truncate()
            return '{"success": true, "message": "Poem was removed from favourites or wasn\'t favourited at all"}'
        else:
            for line in fo:
                if line == favstring:
                    return '{"success": true, "message": "Poem was already favourited!"}'
            fo.write(favstring)

            return '{"success": true, "message": "Favourite was added!"}'

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Server application to provide an overview \
                                                  over a training run and to enable reviewing and rating poems.')
    parser.add_argument('basepath', nargs='?', default='./data', help='base folder where the run outputs are stored')
    args = parser.parse_args()
    
    BASEPATH = args.basepath
    
    app.run()
    #print(getPoem("imagist_long_9", 200, 10))