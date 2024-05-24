# Encryptigma
**The main goal of this project was not to use common encryption algorithms like AES and RSA. The primary aim was to create something unique and original, albeit simple. By the way, during the development process, a "destroy" function for encrypted files was accidentally implemented.**

Encryptigma is a simple console application that provides basic encryption and decryption functionalities using a randomized key generator. The application encrypts text input by the user and saves the encrypted text to a file. It can also decrypt previously encrypted text from a file.

## Features

- **Encryption**: Encrypts user-provided text and saves it to a file on the desktop.
- **Decryption**: Decrypts text from a specified file.
- **Randomized Key Generation**: Generates a unique encryption key based on the current time.

## How It Works

### Encryption

1. The user selects the encryption option.
2. The application prompts the user to enter the text to be encrypted.
3. An encryption key is generated based on the current time.
4. The text is encrypted using the generated key.
5. The encrypted text is saved to a file named `encrypted_text.txt` on the desktop.

### Decryption

1. The user selects the decryption option.
2. The application prompts the user to provide the path to the encrypted file.
3. The creation time of the file is used to recreate the encryption key.
4. The text is decrypted using the recreated key.
5. The decrypted text is displayed to the user.

## Getting Started

### Prerequisites

- .NET SDK installed on your machine.

**For Testing Purposes:**

For Testing Purposes you can download the executable file `Encryptigma.exe`

### `Program.cs`

The entry point of the application. It handles user input and triggers the encryption or decryption process based on user selection.

### `RandomizedEncryption.cs`

Contains the `RandomizedEncryption` class, which handles the encryption and decryption of text using a randomly generated key.

### `PcTime.cs`

Provides the current time formatted as `HHmm`, which is used as a seed for the random key generator.

### `KeyGenerator.cs`

Generates the encryption and decryption keys based on a given seed. The keys are stored in dictionaries for quick lookup.

### `FileManager.cs`

Handles file operations, such as saving the encrypted text to a file and reading from a file during decryption.

## Example Usage

### Encryption

1. Run the application.
2. Select `1` for encryption.
3. Enter the text to be encrypted.
4. The application will display the original text, the encrypted text, and the decrypted text (for verification).
5. The encrypted text is saved to `encrypted_text.txt` on the desktop.

### Decryption

1. Run the application.
2. Select `2` for decryption.
3. Provide the path to the encrypted file.
4. The application will display the decrypted text.

## Potential Issues

When moving the encrypted file to a different folder or location, there might be issues with decryption due to the dependency on the file creation time for generating the decryption key. (bug has been found and is in the process of being fixed)

## Contributing

Feel free to fork this repository and submit pull requests. For major changes, please open an issue first to discuss what you would like to change.

## License

This project is licensed under the MIT License.

---

For any questions or feedback, please contact [Serafim Petrov] at [serafimspetrovs@gmail.com].

Happy encrypting!
