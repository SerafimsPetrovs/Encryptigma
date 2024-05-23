using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Encryptigma
{
    public class KeyGenerator
    {
        private Random random;

        public Dictionary<char, char> EncryptionKey { get; private set; }
        public Dictionary<char, char> DecryptionKey { get; private set; }

        public KeyGenerator(int seed)
        {
            random = new Random(seed);
            EncryptionKey = new Dictionary<char, char>();
            DecryptionKey = new Dictionary<char, char>();

            GenerateKeys();
        }

        private void GenerateKeys()
        {
            char[] alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".ToCharArray();
            List<char> remainingChars = new List<char>(alphabet);

            for (int i = 0; i < alphabet.Length; i++)
            {
                int index = random.Next(remainingChars.Count);
                char selectedChar = remainingChars[index];

                EncryptionKey[alphabet[i]] = selectedChar;
                DecryptionKey[selectedChar] = alphabet[i];

                remainingChars.RemoveAt(index);
            }
        }
    }
}