/// Turns a spoken expense note into expense lines, on the phone (no AI, no cost).
///
/// "Lunch 250 and auto 80"            -> Lunch ₹250 (Food), Auto ₹80 (Transport)
/// "Spent 1,200 on groceries yesterday" -> Groceries ₹1,200, dated yesterday
/// "chai 20 rupees, samosa 30"        -> two lines
/// "petrol 2k kal"                    -> Petrol ₹2,000, yesterday
library;

class VoiceLine {
  final String name;
  final double amount;
  final String categoryId;
  const VoiceLine(this.name, this.amount, this.categoryId);
}

class VoiceNote {
  final List<VoiceLine> lines;
  final int daysAgo; // 0 today, 1 yesterday, 2 day before
  const VoiceNote(this.lines, this.daysAgo);
}

VoiceNote parseVoiceNote(String spoken) {
  var text = ' ${spoken.toLowerCase().replaceAll('₹', ' ₹ ')} ';

  // When: said anywhere in the sentence.
  var daysAgo = 0;
  for (final d in _dayWords.entries) {
    final re = RegExp('\\b(?:${d.key})\\b');
    if (re.hasMatch(text)) {
      daysAgo = d.value;
      text = text.replaceAll(re, ' ');
      break;
    }
  }

  text = _wordsToNumbers(text);
  // "2k" / "1.5k" -> 2000 / 1500; "1,200" -> 1200; "250/-" -> 250
  text = text.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s?k\b'),
      (m) => (double.parse(m.group(1)!) * 1000).toStringAsFixed(0));
  text = text.replaceAllMapped(RegExp(r'(\d),(\d)'), (m) => '${m.group(1)}${m.group(2)}');
  text = text.replaceAll('/-', ' ');

  final segments = text.split(RegExp(r'\s*(?:,|;|\band\b|\baur\b|\bplus\b|&|\bthen\b|\bphir\b)\s*'));
  final lines = <VoiceLine>[];
  var pendingName = '';
  for (final seg in segments) {
    final amounts = RegExp(r'\d+(?:\.\d{1,2})?').allMatches(seg).toList();
    final name = _cleanName(seg.replaceAll(RegExp(r'\d+(?:\.\d{1,2})?'), ' '));
    if (amounts.isEmpty) {
      // "lunch and dinner 500": a name with no amount joins the next line.
      if (name.isNotEmpty) pendingName = pendingName.isEmpty ? name : '$pendingName and $name';
      continue;
    }
    final amount = double.parse(amounts.first.group(0)!);
    if (amount <= 0) continue;
    final full = [pendingName, name].where((s) => s.isNotEmpty).join(' and ');
    pendingName = '';
    final label = full.isEmpty ? 'Expense' : _title(full);
    lines.add(VoiceLine(label, amount, guessCategory(full)));
  }
  return VoiceNote(lines, daysAgo);
}

/// Category from words in the name. "other" when nothing matches.
String guessCategory(String name) {
  final n = ' ${name.toLowerCase()} ';
  for (final e in _categoryWords.entries) {
    for (final w in e.value) {
      if (n.contains(' $w ') || n.contains(' ${w}s ')) return e.key;
    }
  }
  return 'other';
}

String _cleanName(String s) {
  var t = ' $s ';
  t = t.replaceAll(RegExp(r'[₹.!?"]'), ' ');
  t = t.replaceAll(RegExp('\\b(?:${_filler.join('|')})\\b'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _title(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

const _dayWords = <String, int>{
  'day before yesterday|parso|parson': 2,
  'yesterday|kal|last night': 1,
  'today|aaj|this morning|tonight|this evening': 0,
};

const _filler = [
  'i', 'i\'ve', 'have', 'had', 'just', 'spent', 'spend', 'paid', 'pay', 'gave', 'given', 'bought', 'buy', 'got',
  'for', 'on', 'at', 'to', 'of', 'the', 'a', 'an', 'my', 'some', 'worth', 'around', 'about', 'total', 'was', 'is',
  'rupees', 'rupee', 'rupaye', 'rupay', 'rs', 'inr', 'bucks', 'ka', 'ki', 'ke', 'mein', 'me', 'ko', 'diye', 'diya',
  'kharcha', 'kharch', 'kiya', 'liya', 'liye', 'expense', 'note', 'add', 'please', 'only',
];

/// Simple spoken numbers, in case the phone writes them as words: "two hundred fifty" -> 250.
String _wordsToNumbers(String text) {
  const small = {
    'zero': 0, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7, 'eight': 8, 'nine': 9,
    'ten': 10, 'eleven': 11, 'twelve': 12, 'thirteen': 13, 'fourteen': 14, 'fifteen': 15, 'sixteen': 16,
    'seventeen': 17, 'eighteen': 18, 'nineteen': 19, 'twenty': 20, 'thirty': 30, 'forty': 40, 'fifty': 50,
    'sixty': 60, 'seventy': 70, 'eighty': 80, 'ninety': 90,
  };
  const big = {'hundred': 100, 'thousand': 1000, 'lakh': 100000};
  final words = [...small.keys, ...big.keys].join('|');
  return text.replaceAllMapped(RegExp('\\b(?:(?:$words)(?:\\s+|-)?)+\\b'), (m) {
    var total = 0, current = 0;
    for (final w in m.group(0)!.trim().split(RegExp(r'[\s-]+'))) {
      if (small.containsKey(w)) {
        current += small[w]!;
      } else if (w == 'hundred') {
        current = (current == 0 ? 1 : current) * 100;
      } else if (big.containsKey(w)) {
        total += (current == 0 ? 1 : current) * big[w]!;
        current = 0;
      }
    }
    return ' ${total + current} ';
  });
}

const _categoryWords = <String, List<String>>{
  'groceries': [
    'grocery', 'groceries', 'milk', 'bread', 'egg', 'eggs', 'vegetable', 'vegetables', 'sabzi', 'sabji', 'fruit',
    'fruits', 'rice', 'atta', 'dal', 'oil', 'kirana', 'bigbasket', 'blinkit', 'zepto', 'dmart', 'curd', 'paneer',
  ],
  'food': [
    'lunch', 'dinner', 'breakfast', 'chai', 'tea', 'coffee', 'snack', 'samosa', 'pizza', 'burger', 'swiggy', 'zomato',
    'restaurant', 'food', 'biryani', 'juice', 'ice cream', 'dosa', 'thali', 'meal', 'canteen', 'cafe', 'momos',
    'pani puri', 'vada pav', 'sweets', 'mithai',
  ],
  'transport': [
    'auto', 'rickshaw', 'uber', 'ola', 'rapido', 'cab', 'taxi', 'bus', 'metro', 'train', 'petrol', 'diesel', 'fuel',
    'parking', 'toll', 'fare', 'flight',
  ],
  'bills': [
    'electricity', 'bill', 'recharge', 'mobile', 'wifi', 'internet', 'broadband', 'rent', 'gas', 'cylinder', 'water',
    'dth', 'emi', 'maintenance',
  ],
  'health': ['medicine', 'medicines', 'doctor', 'pharmacy', 'hospital', 'medical', 'apollo', 'tablet', 'clinic', 'dawai'],
  'cosmetics': ['shampoo', 'soap', 'face wash', 'facewash', 'cream', 'lipstick', 'makeup', 'cosmetic', 'perfume', 'nykaa', 'salon', 'haircut'],
  'shopping': ['clothes', 'shirt', 'shoes', 'jeans', 'kurta', 'saree', 'amazon', 'flipkart', 'myntra', 'shopping', 'gift', 'bag'],
  'entertainment': ['movie', 'netflix', 'cinema', 'pvr', 'game', 'concert', 'spotify', 'hotstar', 'party', 'outing'],
};
