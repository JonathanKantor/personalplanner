"""Log in or sign up. Same accounts as the web app and CLI.

On a phone, `jacLogin` keeps the session token in secure storage
(expo-secure-store), so you stay logged in between launches.
"""

import from "@jac/mobui" { View, Text, TextInput, ScrollView, Pressable }
import from "@jac/runtime" { jacLogin, jacSignup, SignupResult }
import from ..theme { C, S, F, styles }
import from ..components.kit { Button, Card }
import from ..components.MorrowFace { MorrowFace }

def:pub LoginScreen(onLoggedIn: Callable[[], None], pointer: list[float]) -> JsxElement {
    has username: str = "",
        password: str = "",
        signing_up: bool = False,
        error: str = "",
        busy: bool = False;

    async def submit {
        ok: bool = False;                       # declared before await (see jac-cl-auth)
        created: SignupResult | None = None;
        error = "";
        if not username.strip() or not password {
            error = "Enter a username and password.";
            return;
        }
        busy = True;
        if signing_up {
            created = await jacSignup(username.strip(), password);
            if not created.success {
                busy = False;
                error = created.error or "Could not create the account (username taken?)";
                return;
            }
        }
        ok = await jacLogin(username.strip(), password);   # signup alone doesn't log in
        busy = False;
        if ok {
            onLoggedIn();
        } else {
            error = "Wrong username or password.";
        }
    }

    <ScrollView style={styles.screen} contentContainerStyle={[styles.content, {"paddingTop": S.xxl * 2}]}>
        <Card>
            <View style={[styles.row, {"gap": S.md, "marginBottom": S.md}]}>
                <MorrowFace pointer={pointer}/>
                <Text style={{"color": C.text, "fontSize": F.lg, "fontWeight": "700"}}>morrow</Text>
            </View>
            <Text style={[styles.h1, {"fontSize": F.xl}]}>{"Create your account" if signing_up else "Welcome back"}</Text>
            <Text style={styles.subtitle}>{"A little more room to think, starting now." if signing_up else "Log in to see your week."}</Text>
            <TextInput testID="username" style={styles.input} value={username} placeholder="Username"
                placeholderTextColor={C.subtle} autoCapitalize="none"
                onChangeText={lambda (t: str) { username = t; }} />
            <TextInput testID="password" style={styles.input} value={password} placeholder="Password"
                placeholderTextColor={C.subtle} secureTextEntry={True}
                onChangeText={lambda (t: str) { password = t; }} onSubmitEditing={submit} />
            {(<Text style={styles.error}>{error}</Text>) if error else <View/>}
            <Button label={"Sign up" if signing_up else "Log in"} variant="primary" onPress={submit} disabled={busy} testID="login-submit"/>
            <Pressable onPress={lambda { signing_up = not signing_up; error = ""; }}>
                <Text style={{"color": C.accent, "fontSize": F.sm, "textAlign": "center", "marginTop": S.sm}}>
                    {"Have an account? Log in" if signing_up else "New here? Create an account"}
                </Text>
            </Pressable>
        </Card>
    </ScrollView>
}
