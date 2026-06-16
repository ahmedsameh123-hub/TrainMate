import streamlit as st
# from Audio import text_to_speech, get_audio
import cv2
import tempfile
import ExerciseAiTrainer as exercise
import time
from chatbot import chat_ui
from auth.auth_ui import auth_page

# Function for user info page
def user_info_page():
    if "authenticated" in st.session_state and st.session_state.authenticated:
        st.title("Enter Your Information")

        with st.form(key='user_info_form'):
            age = st.number_input("Enter your age", min_value=1, max_value=120)
            sex = st.selectbox("Select your sex", ["Male", "Female"])
            height = st.number_input("Enter your height (in cm)", min_value=50, max_value=250)
            weight = st.number_input("Enter your weight (in kg)", min_value=10, max_value=300)

            submit_button = st.form_submit_button(label="Submit")

            if submit_button:
                # Save the data to session state
                st.session_state.user_data = {
                    "age": age,
                    "sex": sex,
                    "height": height,
                    "weight": weight
                }
                st.success("Your information has been saved!")
                st.write("Thank you for providing your details.")
    else:
        st.warning("You need to log in first!")


def main():
    

    
    # Set configuration for the theme before any other Streamlit command
    st.set_page_config(page_title='Smart Gym Assistant – Train Mate', layout='centered')
   
    if "authenticated" not in st.session_state or not st.session_state.authenticated:
        auth_page()
        return
    
    if st.sidebar.button("Logout"):
        st.session_state.authenticated = False
        st.session_state.user_data = None  # Clear user data
        st.rerun()


    if "user_data" not in st.session_state:
        user_info_page()  # Show form for age, sex, height, and weight
    else:
        st.write(f"Welcome {st.session_state.user_data['sex']}!")
        st.write(f"Age: {st.session_state.user_data['age']}, Height: {st.session_state.user_data['height']} cm, Weight: {st.session_state.user_data['weight']} kg")


    # Define App Title and Structure
    st.title('Smart Gym Assistant – Train Mate')

    # 2 Options: Video, WebCam, Auto Classify, chatbot
    options = st.sidebar.selectbox('Select Option', ('Video', 'WebCam', 'Auto Classify', 'chatbot'))

    if options == 'chatbot':
        st.markdown('-------')
        st.markdown("The chatbot can make mistakes. Check important info.")
        chat_ui()
        return

    # Define Operations if Video Option is selected
    if options == 'Video':
        st.markdown('-------')

        st.write('## Upload your video and select the correct type of Exercise to count repetitions')
        st.write("")
        st.write('Please ensure you are clearly visible and facing the camera directly. This will help the AI accurately track your movements.')


        st.sidebar.markdown('-------')

        # User can select different types of exercise
        exercise_options = st.sidebar.selectbox(
            'Select Exercise', ('Bicept Curl', 'Push Up', 'Squat', 'Shoulder Press')
        )

        st.sidebar.markdown('-------')

        # User can upload a video:
        video_file_buffer = st.sidebar.file_uploader("Upload a video", type=["mp4", "mov", 'avi', 'asf', 'm4v'])
        tfflie = tempfile.NamedTemporaryFile(delete=False)
        cap = None

        if video_file_buffer is not None:
         tfflie.write(video_file_buffer.read())
         cap = cv2.VideoCapture(tfflie.name)

        if cap is None or not cap.isOpened():
         st.error("Please upload a valid video file before starting analysis.")
         return


        # if no video uploaded then use a demo
        # if not video_file_buffer:
        #     DEMO_VIDEO = 'demo_2.mp4'
        #     cap = cv2.VideoCapture(DEMO_VIDEO)
        #     tfflie.name = DEMO_VIDEO

        # if video is uploaded then analyze the video
        # else:
        #     tfflie.write(video_file_buffer.read())
        #     cap = cv2.VideoCapture(tfflie.name)
        # st.markdown('-------')

        # Visualize Video before analysis
        st.sidebar.text('Input Video')
        st.sidebar.video(tfflie.name)

        st.markdown('## Input Video')
        st.video(tfflie.name)

        st.markdown('-------')

        # Visualize Video after analysis (analysis based on the selected exercise)
        st.markdown(' ## Output Video')
        if exercise_options == 'Bicept Curl':
            exer = exercise.Exercise()
            counter, stage_right, stage_left = 0, None, None
            exer.bicept_curl(cap, is_video=True, counter=counter, stage_right=stage_right, stage_left=stage_left)

        elif exercise_options == 'Push Up':
            st.write("The exercise need to be filmed showing your left side or facing frontally")
            exer = exercise.Exercise()
            counter, stage = 0, None
            exer.push_up(cap, is_video=True, counter=counter, stage=stage)

        elif exercise_options == 'Squat':
            exer = exercise.Exercise()
            counter, stage = 0, None
            exer.squat(cap, is_video=True, counter=counter, stage=stage)

        elif exercise_options == 'Shoulder Press':
            exer = exercise.Exercise()
            counter, stage = 0, None
            exer.shoulder_press(cap, is_video=True, counter=counter, stage=stage)
    
    # Added new section for Auto Classify
    elif options == 'Auto Classify':
        st.markdown('-------')
        st.write('Click button to start automatic exercise classification and repetition counting')
        st.markdown('-------')
        st.write("Please ensure you are clearly visible and facing the camera directly. This will help the AI accurately track your movements.")
        auto_classify_button = st.button('Start Auto Classification')

        if auto_classify_button:
            time.sleep(2)
            exer = exercise.Exercise()
            exer.auto_classify_and_count()

    # Define Operation if webcam option is selected
    elif options == 'WebCam':
        st.markdown('-------')

        st.sidebar.markdown('-------')

        # User can select different exercises
        exercise_general = st.sidebar.selectbox(
            'Select Exercise', ('Bicept Curl', 'Push Up', 'Squat', 'Shoulder Press')
        )

        # Define a button for start the analysis (pose estimation) on the webcam
        # st.write(' Click button and say "yes" when you are in the correct position for training')
        # button = st.button('Activate AI Trainer')

        # st.markdown('-------')

        # New button for direct activation
        st.write(' Click button to start training')
        start_button = st.button('Start Exercise')

        # # Visualize video that explain the correct forms for the exercises
        # if exercise_general == 'Bicept Curl':
        #     st.write('## Bicept Curl Execution Video')
        #     st.video('curl_form.mp4')

        # elif exercise_general == 'Push Up':
        #     st.write('## Push Up Execution Video')
        #     st.video('push_up_form.mp4')

        # elif exercise_general == 'Squat':
        #     st.write('## Squat Execution Video')
        #     st.video('squat_form_2.mp4')

        # elif exercise_general == 'Shoulder Press':
        #     st.write('## Shoulder Press Execution')
        #     st.video('shoulder_press_form.mp4')

        if start_button:
            time.sleep(2)  # Add a delay of 2 seconds
            ready = True
            # for each type of exercise call the method that analyze that exercise
            if exercise_general == 'Bicept Curl':
                while ready:
                    cap = cv2.VideoCapture(0)
                    exer = exercise.Exercise()
                    counter, stage_right, stage_left = 0, None, None
                    exer.bicept_curl(cap, counter=counter, stage_right=stage_right, stage_left=stage_left)
                    break

            elif exercise_general == 'Push Up':
                while ready:
                    cap = cv2.VideoCapture(0)
                    exer = exercise.Exercise()
                    counter, stage = 0, None
                    exer.push_up(cap, counter=counter, stage=stage)
                    break

            elif exercise_general == 'Squat':
                while ready:
                    cap = cv2.VideoCapture(0)
                    exer = exercise.Exercise()
                    counter, stage = 0, None
                    exer.squat(cap, counter=counter, stage=stage)
                    break

            elif exercise_general == 'Shoulder Press':
                while ready:
                    cap = cv2.VideoCapture(0)
                    exer = exercise.Exercise()
                    counter, stage = 0, None
                    exer.shoulder_press(cap, counter=counter, stage=stage)
                    break

if __name__ == '__main__':
    def load_css():
        with open("static/styles.css", "r") as f:
            css = f"<style>{f.read()}</style>"
            st.markdown(css, unsafe_allow_html=True)
    main()
