from gensim.models import word2vec
import argparse
import re
import logging

logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.INFO)
 

ap = argparse.ArgumentParser()
ap.add_argument("file")
args = ap.parse_args()

splitter = re.compile("[\w']+|[^\w\s]+")

with open(args.file, "r") as fo:
	sentences = map(lambda line : splitter.findall(line.lower()), fo)
	wvmodel = word2vec.Word2Vec(sentences)

print (wvmodel.wv.most_similar(['man']))
print (wvmodel.wv.get_vector("man"))

