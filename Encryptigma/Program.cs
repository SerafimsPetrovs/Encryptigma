using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using System.Text;
using System.Threading.Tasks;

namespace Encryptigma
{
    public class Program
    {
        public static void Main()
        {
            //test
            Console.WriteLine("Select 1: Encryption ||| 2: Decryption");
            int choice = int.Parse(Console.ReadLine());
            switch (choice)
            {
                case 1:
                    PerformEncryption();
                    break;
                case 2:
                    PerformDecryption();
                    break;
                default:
                    Console.WriteLine("Invalid choice. Please select either 1 or 2.");
                    break;
            }
            Console.ReadLine();
        }

        private static void PerformEncryption()
        {
            PcTime pcTime = new PcTime();
            string desktopPath = Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
            string filePath = Path.Combine(desktopPath, "encrypted_text.txt");

            Console.WriteLine($"File will be saved on Desktop: {filePath}");

            Console.WriteLine("Copy and paste or write the text to be encrypted:");
            string originalText = Console.ReadLine();

            int seed = int.Parse(pcTime.GetFormattedTime());
            RandomizedEncryption enigma = new RandomizedEncryption(seed);
            string encryptedText = enigma.Encrypt(originalText);
            string decryptedText = enigma.Decrypt(encryptedText);

            Console.WriteLine($"Original: {originalText}");
            Console.WriteLine($"Encrypted: {encryptedText}");
            Console.WriteLine($"Decrypted: {decryptedText}");

            FileManager.SaveToFile(filePath, encryptedText);
        }
        private static void PerformDecryption()
        {
            Console.WriteLine("Specify the path of the encrypted file:");
            string encryptedFilePath = Console.ReadLine();

            if (File.Exists(encryptedFilePath))
            {
                DateTime creationTime = File.GetCreationTime(encryptedFilePath);
                int seed = creationTime.Hour * 100 + creationTime.Minute;
                string encryptedText = File.ReadAllText(encryptedFilePath);
                RandomizedEncryption enigma = new RandomizedEncryption(seed);
                string decryptedText = enigma.Decrypt(encryptedText);

                Console.WriteLine($"Decrypted text: {decryptedText}");
            }
            else
            {
                Console.WriteLine("File not found.");
            }
        }
    }
}
