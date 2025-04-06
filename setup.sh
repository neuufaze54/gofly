#!/bin/bash

# Add Mozilla Team PPA for Firefox
sudo add-apt-repository -y ppa:mozillateam/ppa

sudo apt -y --fix-broken install

# Update package list
sudo apt update

# Install Firefox and required packages
sudo apt install -y firefox xdotool zip curl jq xclip unzip git python3-dev python3-tk python3-pip gnome-screenshot python3.8-venv

# Create Python virtual environment
python3 -m venv myenv

# Activate the virtual environment
source myenv/bin/activate

# Ensure .Xauthority file is created
touch ~/.Xauthority

# Install Python packages
pip install pyautogui
pip install --upgrade pillow
pip install opencv-python-headless
pip install requests

# Output completion message
echo "All packages installed and environment set up successfully."
