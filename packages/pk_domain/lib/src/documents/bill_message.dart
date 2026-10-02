/// The few lines that travel with a bill sent again (M30).
///
/// A PDF or a picture arrives on a customer's phone as a file with a name.
/// What makes it read as *their* bill, in the chat list, before anybody opens
/// anything, is the text beside it: who it is from, which bill, what day, and
/// what is still owed. It is also the whole message when the shopkeeper sends
/// only that, straight into the customer's chat.
///
/// Roman Urdu, for the same reason the reminder is: it is what the
/// shopkeeper's customers read, and what the shopkeeper would have typed.
///
/// Nothing here talks to anybody. It builds a string from what the receipt
/// already says, so the message and the paper cannot disagree.
library;

import '../ports/receipt.dart';

/// What to write beside [receipt] when it is sent.
///
/// Amounts paid and still owed only for a bill. A quotation or a challan has
/// nothing paid against it yet, and "Baqi: Rs 0.00" on a quotation reads as
/// though it had been settled.
String billMessage(ReceiptData receipt) {
  final name = receipt.customerName?.trim();
  final isBill = switch (receipt.docTitle) {
    // An order (M41) is goods asked for, not goods sold: nothing is owed
    // on it, and its advance is a receipt of its own.
    'Quotation' ||
    'Delivery Challan' ||
    'Purchase Order' ||
    'Sale Order' => false,
    _ => true,
  };

  final buffer = StringBuffer();
  if (name != null && name.isNotEmpty) {
    buffer.write('Assalam-o-Alaikum $name,\n\n');
  } else {
    buffer.write('Assalam-o-Alaikum,\n\n');
  }
  buffer
    ..write('${receipt.shop.name} se ${_what(receipt.docTitle)} ')
    ..write('${receipt.docNo}\n')
    ..write('Tareekh: ${receipt.dateTimeLabel}\n')
    ..write('Kul: Rs ${receipt.total.amountOnly}\n');

  if (receipt.isCancelled) {
    // Said in words as well as on the paper, and nothing about what is owed:
    // "Baqi" beside a cancelled bill is a demand for money nobody owes.
    buffer.write(
      'Yeh bill mansookh ho chuka hai, is par kuch ada nahi karna.\n',
    );
  } else if (isBill) {
    buffer.write('Ada kiye: Rs ${receipt.paid.amountOnly}\n');
    if (receipt.balance.isPositive) {
      buffer.write('Baqi: Rs ${receipt.balance.amountOnly}\n');
    }
  }

  buffer.write('\nShukriya.');
  return buffer.toString();
}

/// The paper's title as a shopkeeper would say it in the message.
///
/// Keyed on the title the receipt read already chose, which is the one place
/// a document's kind becomes words; anything it does not name is a bill.
String _what(String docTitle) => switch (docTitle) {
  'Quotation' => 'quotation',
  'Delivery Challan' => 'challan',
  'Purchase Bill' => 'kharidari ka bill',
  'Debit Note' => 'charge',
  'Purchase Order' => 'order',
  'Sale Order' => 'order',
  _ => 'bill',
};
