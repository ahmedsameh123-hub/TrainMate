import streamlit as st
from groq import Groq

# 🔑 Put your Groq API key here
GROQ_API_KEY = "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"

client = Groq(api_key=GROQ_API_KEY)


def chat_ui():
    st.title("Ask me anything about Fitness 🤖")
    st.caption("The chatbot can make mistakes. Check important information.")

    if "messages" not in st.session_state:
        st.session_state.messages = [
            {
                "role": "system",
                "content": (
                    "You are a professional fitness coach. "
                    "You help users with correct exercise form, posture, "
                    "repetition counting, injury prevention, and workout advice."
                ),
            }
        ]

    # Show chat history
    for msg in st.session_state.messages[1:]:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

    user_prompt = st.chat_input("Ask about exercises, posture, reps, or training tips")

    if user_prompt:
        st.session_state.messages.append(
            {"role": "user", "content": user_prompt}
        )

        with st.chat_message("user"):
            st.markdown(user_prompt)

        response = client.chat.completions.create(
            model="llama-3.1-8b-instant",  # ✅ FIXED MODEL
            messages=st.session_state.messages,
            temperature=0.5,
        )

        reply = response.choices[0].message.content

        st.session_state.messages.append(
            {"role": "assistant", "content": reply}
        )

        with st.chat_message("assistant"):
            st.markdown(reply)


if __name__ == "__main__":
    chat_ui()
