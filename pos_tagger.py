import sys
import spacy

# Load English tokenizer, POS tagger, etc.
nlp = spacy.load("en_core_web_sm")

# Read input phrase from stdin
text = sys.stdin.readline().strip()
print(text)
doc = nlp(text)
print(doc)
# Output tokens and POS tags
for token in doc:
    print(f"{token.text}\t{token.pos_}")
