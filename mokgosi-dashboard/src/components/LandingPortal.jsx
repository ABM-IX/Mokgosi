import React, { useState } from 'react';

/**
 * Public sign-in page. It says who the console is for and nothing about how the app on a
 * person's phone is disguised: anyone can open this page, including someone causing harm.
 */
export default function LandingPortal({ onSignIn, error, demoMode = false }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [localError, setLocalError] = useState('');

  async function handleSubmit(e) {
    e.preventDefault();
    setLocalError('');
    if (!email.trim()) {
      setLocalError(demoMode ? 'Enter a name to use in demo mode.' : 'Enter the email address you were invited with.');
      return;
    }
    if (!password && !demoMode) {
      setLocalError('Enter your password.');
      return;
    }
    setLoading(true);
    try {
      await onSignIn(email.trim(), password);
    } catch (err) {
      setLocalError(err.message || 'Sign-in failed. Check your email and password.');
    } finally {
      setLoading(false);
    }
  }

  const displayError = localError || error;

  return (
    <main className="signin">
      <section className="signin-intro">
        <span className="wordmark">Mokgosi</span>
        <h1>Responder console</h1>
        <p>
          For police officers, social workers and support organisations who respond to alerts raised
          through the Mokgosi app in Botswana.
        </p>
        <ol className="signin-steps">
          <li>Someone raises an alert from their phone, openly or discreetly.</li>
          <li>Their trusted contacts are told, and the alert appears here.</li>
          <li>You acknowledge it, follow the guidance for that kind of alert, and record what was done.</li>
        </ol>
        <p className="signin-foot">
          Access is by invitation. If you need an account, ask the coordinator at your organisation.
        </p>
      </section>

      <section className="signin-card" aria-labelledby="signin-heading">
        <h2 id="signin-heading">Sign in</h2>
        {displayError && (
          <div className="signin-error" role="alert">
            {displayError}
          </div>
        )}
        <form onSubmit={handleSubmit}>
          <label className="field">
            <span>{demoMode ? 'Name or email' : 'Email'}</span>
            <input
              id="portal-email"
              type="text"
              autoComplete="username"
              placeholder={demoMode ? 'Any name works in demo mode' : 'name@organisation.org.bw'}
              value={email}
              onChange={(e) => setEmail(e.target.value)}
            />
          </label>
          <label className="field">
            <span>Password</span>
            <input
              id="portal-password"
              type="password"
              autoComplete="current-password"
              placeholder={demoMode ? 'Not needed in demo mode' : ''}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>
          <button type="submit" className="btn btn-primary btn-block" disabled={loading}>
            {loading ? 'Signing in…' : 'Sign in'}
          </button>
        </form>
        {demoMode && (
          <p className="demo-box">
            Demo mode is on. Sign in with any name to look around; every incident you will see is sample data.
          </p>
        )}
      </section>
    </main>
  );
}
