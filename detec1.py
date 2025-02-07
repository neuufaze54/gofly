import pyautogui
import time
import sys

def wait_for_web_button(image_path='micros_button.png', confidence_level=0.8):
    """Continuously wait for the web button to appear and click it once found."""
    print(f"Waiting for {image_path} to appear...")

    while True:
        # Check if the button is on the screen
        button_location = pyautogui.locateCenterOnScreen(image_path, confidence=confidence_level, grayscale=True)
        if button_location:
            print(f"{image_path} found at {button_location}. Clicking...")
            sys.exit(0)  # Exit with success once the button is found

        # Brief pause before checking again
        time.sleep(0.5)
        print(f"{image_path} not found, retrying...")

if __name__ == "__main__":
    wait_for_web_button()
