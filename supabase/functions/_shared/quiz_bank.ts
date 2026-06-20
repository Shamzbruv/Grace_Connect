export type QuizQuestion = {
  question: string;
  options: [string, string, string, string];
  correct_option_index: number;
  correct_answer: string;
  explanation: string;
  scripture_references: string[];
  category: string;
  difficulty: "easy" | "medium" | "hard";
};

export const fallbackQuizQuestions: QuizQuestion[] = [
  {
    question: "Who built the ark before the flood?",
    options: ["Moses", "Noah", "Abraham", "David"],
    correct_option_index: 1,
    correct_answer: "Noah",
    explanation: "Noah obeyed God and built the ark before the flood came.",
    scripture_references: ["Genesis 6:13-22"],
    category: "Bible people",
    difficulty: "easy",
  },
  {
    question: "Where was Jesus born?",
    options: ["Nazareth", "Jerusalem", "Bethlehem", "Capernaum"],
    correct_option_index: 2,
    correct_answer: "Bethlehem",
    explanation: "The Gospel accounts identify Bethlehem as the birthplace of Jesus.",
    scripture_references: ["Matthew 2:1", "Luke 2:4-7"],
    category: "Jesus",
    difficulty: "easy",
  },
  {
    question: "Which sea did Israel cross after leaving Egypt?",
    options: ["Dead Sea", "Sea of Galilee", "Mediterranean Sea", "Red Sea"],
    correct_option_index: 3,
    correct_answer: "Red Sea",
    explanation: "God delivered Israel through the Red Sea as they escaped Egypt.",
    scripture_references: ["Exodus 14:21-22"],
    category: "Bible events",
    difficulty: "easy",
  },
  {
    question: "Who was thrown into a den of lions?",
    options: ["Daniel", "Joseph", "Elijah", "Samuel"],
    correct_option_index: 0,
    correct_answer: "Daniel",
    explanation: "Daniel was placed in the lions' den, and God preserved him.",
    scripture_references: ["Daniel 6:16-23"],
    category: "Bible people",
    difficulty: "easy",
  },
  {
    question: "Which book begins with creation?",
    options: ["Exodus", "Genesis", "Psalms", "John"],
    correct_option_index: 1,
    correct_answer: "Genesis",
    explanation: "Genesis opens with God's creation of the heavens and the earth.",
    scripture_references: ["Genesis 1:1"],
    category: "Bible books",
    difficulty: "easy",
  },
  {
    question: "Who led Israel after Moses died?",
    options: ["Aaron", "Joshua", "Gideon", "Solomon"],
    correct_option_index: 1,
    correct_answer: "Joshua",
    explanation: "Joshua was appointed to lead Israel after Moses.",
    scripture_references: ["Joshua 1:1-2"],
    category: "Bible people",
    difficulty: "medium",
  },
  {
    question: "What did Jesus use to feed the five thousand?",
    options: ["Manna and quail", "Seven loaves", "Five loaves and two fish", "Bread and wine"],
    correct_option_index: 2,
    correct_answer: "Five loaves and two fish",
    explanation: "Jesus multiplied five loaves and two fish to feed the crowd.",
    scripture_references: ["John 6:9-13"],
    category: "Miracles",
    difficulty: "easy",
  },
  {
    question: "Who denied knowing Jesus three times?",
    options: ["Peter", "Thomas", "James", "Judas"],
    correct_option_index: 0,
    correct_answer: "Peter",
    explanation: "Peter denied Jesus three times before the rooster crowed.",
    scripture_references: ["Luke 22:54-62"],
    category: "New Testament",
    difficulty: "easy",
  },
  {
    question: "What fruit of the Spirit is listed first in Galatians 5?",
    options: ["Peace", "Joy", "Love", "Faithfulness"],
    correct_option_index: 2,
    correct_answer: "Love",
    explanation: "Love is the first fruit named in Paul's list.",
    scripture_references: ["Galatians 5:22"],
    category: "Early church",
    difficulty: "medium",
  },
  {
    question: "Which prophet confronted the prophets of Baal on Mount Carmel?",
    options: ["Isaiah", "Elijah", "Jeremiah", "Elisha"],
    correct_option_index: 1,
    correct_answer: "Elijah",
    explanation: "Elijah challenged the prophets of Baal and called Israel back to the Lord.",
    scripture_references: ["1 Kings 18:20-39"],
    category: "Old Testament",
    difficulty: "medium",
  },
];
