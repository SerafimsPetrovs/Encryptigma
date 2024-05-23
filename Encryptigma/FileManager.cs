using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Encryptigma
{
    public class FileManager
    {
        public static void SaveToFile(string filePath, string text)
        {
            try
            {
                using (StreamWriter writer = new StreamWriter(filePath))
                {
                    writer.WriteLine(text);
                }
                Console.WriteLine("File saved successfully.");
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Error occurred while saving the file: {ex.Message}");
            }
        }
    }
}

