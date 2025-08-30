// MongoDB initialization script
db = db.getSiblingDB('financedb');

// Create a sample collection and insert some test data
db.createCollection('transactions');

// Insert sample data
db.transactions.insertMany([
  {
    date: new Date(),
    amount: 100.50,
    description: "Sample transaction 1",
    category: "groceries",
    type: "expense"
  },
  {
    date: new Date(),
    amount: 2500.00,
    description: "Salary deposit",
    category: "income",
    type: "income"
  },
  {
    date: new Date(),
    amount: 45.20,
    description: "Gas station",
    category: "transport",
    type: "expense"
  }
]);

print("Initialized financedb with sample data");