// login screen
import { styles } from "./Styles";
import { React, useEffect, useState, } from "react";
import { StyleSheet, Text, TouchableOpacity, View } from 'react-native';
import { List, TextInput } from 'react-native-paper';

export const Login = (props) => {

    const nextScreen = () => {
        props.navigation.navigate("FACircle");
    }

    const [v, setV] = useState("hi");
    console.log("login screen2");
    return (
        <View style={styles.container}>
            <Text style={styles.text}>Hi There {v}</Text>
            <TextInput
                value={v}
                onChangeText={(text) => setV(text)}
                style={styles.text}
            >
            </TextInput>
            <TextInput
                value={v}
                onChangeText={(text) => setV(text)}
                style={styles.text}
            >
            </TextInput>
            <List.Accordion
                title="List.Accordion"
                pointerEvents="auto"
                theme={{ colors: { background: 'orange' } }}
                style={{ backgroundColor: 'white', marginBottom: 20 }}
                left={props => <List.Icon {...props} icon="folder" />}
            >
                <List.Item title="first" pointerEvents="box-none" onPress={(e) => { console.log("pressed me: " + e.toString()) }}
                    style={{ backgroundColor: 'white', marginBottom: 20 }} left={props =>

                        <TouchableOpacity style={styles.button} onPress={nextScreen}>
                            <Text style={styles.buttonText}>wa Screen</Text>
                        </TouchableOpacity>
                    } />
                <List.Item
                    pointerEvents="box-none" onPress={(e) => { }}
                    title={<TouchableOpacity pointerEvents="auto" style={styles.button} onPress={nextScreen}>
                        <Text style={styles.buttonText}>SECDTION Screen</Text>
                    </TouchableOpacity>} style={{ backgroundColor: 'white', marginBottom: 20 }} />
            </List.Accordion>

            <TouchableOpacity style={styles.button} onPress={nextScreen}>
                <Text style={styles.buttonText}>Next Screen</Text>
            </TouchableOpacity>
        </View>
    );
}