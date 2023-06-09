// login screen
import { styles } from "./FACircle";
import { React } from "react";
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';

export const Login = (props) => {

    const nextScreen = () => {
        props.navigation.navigate("FACircle");
    }

    return (
        <View style={styles.container}>
            <Text style={styles.text}>Hi There</Text>
            <TouchableOpacity style={styles.button} onPress={nextScreen}>
                <Text style={styles.buttonText}>Next Screen</Text>
            </TouchableOpacity>
        </View>
    );
}