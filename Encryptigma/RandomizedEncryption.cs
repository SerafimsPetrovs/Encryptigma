using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Encryptigma
{
    public class RandomizedEncryption
    {
        private KeyGenerator keyGenerator;
        private Random random;

        public RandomizedEncryption(int seed)
        {
            random = new Random(seed);
            keyGenerator = new KeyGenerator(seed);
        }

        public string Encrypt(string input)
        {
            StringBuilder encrypted = new StringBuilder();

            foreach (char ch in input)
            {
                if (keyGenerator.EncryptionKey.ContainsKey(ch))
                {
                    encrypted.Append(keyGenerator.EncryptionKey[ch]);
                }
                else
                {
                    encrypted.Append(ch);
                }
            }

            return encrypted.ToString();
        }

        public string Decrypt(string input)
        {
            StringBuilder decrypted = new StringBuilder();

            foreach (char ch in input)
            {
                if (keyGenerator.DecryptionKey.ContainsKey(ch))
                {
                    decrypted.Append(keyGenerator.DecryptionKey[ch]);
                }
                else
                {
                    decrypted.Append(ch);
                }
            }

            return decrypted.ToString();
        }
    }
}
