import io

# load text
filename = 'C:\\python-projects\\string-clean\\banana.txt'
file = io.open(filename, 'rU', encoding='utf-8')
text = file.read()
file.close()
'''# alternatively: split into sentences
from nltk import sent_tokenize
sentences = sent_tokenize(text)'''
# split into words
from nltk.tokenize import word_tokenize
tokens = word_tokenize(text)
# convert to lower case
tokens = [w.lower() for w in tokens]
# remove non-alphabetic tokens
words = [word for word in tokens if word.isalpha()]
# save into file
with open('C:\\python-projects\\string-clean\\output.txt', 'a') as output:
    output.write(' '.join(words).encode('utf-8'))
    
print(words[:100])