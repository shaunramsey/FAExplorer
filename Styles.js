import { StyleSheet } from 'react-native';

export const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
        color: '#fff',
        alignItems: 'center',
        justifyContent: 'center',
    },
    text: {
        color: '#fff',
    },
    circles: {
        flexDirection: 'row',
        display: 'flex',
    },
    circle: {
        justifyContent: 'center',
        textAlign: 'center',
        borderColor: '#f90',
        borderWidth: '1px',
        backgroundColor: '#fff',
        color: '#000',
        borderRadius: '50%',
        height: '50px',
        width: '50px',

    },
    circleText: {

    },
    buttonText: {
        color: '#fff',
        fontSize: '24px',
        fontWeight: 'bold',
    },
    status: {
        color: '#f0f',
    },
    button: {
        margin: '40px',
        paddingHorizontal: '30px',
        paddingTop: '1px',
        paddingBottom: '5px',
        borderColor: '#fff',
        borderStyle: 'solid',
        borderWidth: '2px',
        backgroundColor: '#383',
        borderRadius: '20px',

        color: '#afa',
        fontSize: '24px',
        fontWeight: '400',
    },
    inactive: {
        margin: '4px',
        borderWidth: '2px',
        borderColor: '#000',
        borderRadius: '50%',
        backgroundColor: '#fff',
    },
    active: {
        margin: '4px',
        borderWidth: '2px',
        borderColor: '#0ff',
        borderRadius: '50%',
        backgroundColor: '#fff',
    },
    squareShape: {
        width: 100,
        height: 100,
        backgroundColor: "#105f5f",
        marginBottom: 10,
        marginRight: 10,
    }
});



const getPadding = (inputPadding) => {
    let p = inputPadding.split(' ');
    return {
        paddingTop: p[0],
        paddingRight: p[1],
        paddingBottom: p[2],
        paddingLeft: p[3],
        borderColor: "#fff",
        borderWidth: "1px",
    };
}
const buttonStyle = StyleSheet.flatten([getPadding("10px 20px 30px 40px"), styles.button]);